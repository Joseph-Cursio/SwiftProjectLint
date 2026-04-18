import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects functions declared `/// @lint.context replayable` or `/// @lint.context retry_safe`
/// whose body calls a function declared `/// @lint.effect non_idempotent` anywhere in
/// the project. Resolution is cross-file via the shared `EffectSymbolTable`, subject
/// to the table's collision policy.
///
/// ## Cross-file dispatch
/// Conforms to `CrossFilePatternVisitorProtocol`. Walk phase accumulates the symbol
/// table and analysis sites; emission happens in `finalizeAnalysis()` so the per-file
/// dispatcher produces no double-emits.
///
/// Closure-traversal policy mirrors `IdempotencyViolationVisitor` — non-escaping only.
final class NonIdempotentInRetryContextVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {

    let fileCache: [String: SourceFileSyntax]

    private var symbolTable = EffectSymbolTable()
    private var analysisSites: [AnalysisSite] = []

    private struct AnalysisSite {
        let function: FunctionDeclSyntax
        let context: ContextEffect
        let filePath: String
        let locationConverter: SourceLocationConverter
    }

    private var currentFilePath: String = ""
    private var currentLocationConverter: SourceLocationConverter?

    required init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
        super.init(pattern: BasePatternVisitor.placeholderPattern, viewMode: .sourceAccurate)
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.fileCache = [:]
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        currentFilePath = filePath
    }

    override func setSourceLocationConverter(_ converter: SourceLocationConverter) {
        super.setSourceLocationConverter(converter)
        currentLocationConverter = converter
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        symbolTable.merge(source: node)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let context = EffectAnnotationParser.parseContext(leadingTrivia: node.leadingTrivia),
              node.body != nil else {
            return .visitChildren
        }
        let converter = currentLocationConverter
            ?? SourceLocationConverter(fileName: currentFilePath, tree: node.root)
        analysisSites.append(
            AnalysisSite(
                function: node,
                context: context,
                filePath: currentFilePath,
                locationConverter: converter
            )
        )
        return .visitChildren
    }

    func finalizeAnalysis() {
        for site in analysisSites {
            guard let body = site.function.body else { continue }
            analyzeBody(Syntax(body), site: site)
        }
    }

    func analyze() {
        finalizeAnalysis()
    }

    private func analyzeBody(_ syntax: Syntax, site: AnalysisSite) {
        if syntax.is(FunctionDeclSyntax.self) { return }
        if let closure = syntax.as(ClosureExprSyntax.self), isEscapingClosure(closure) {
            return
        }

        if let call = syntax.as(FunctionCallExprSyntax.self),
           let calleeSignature = FunctionSignature.from(call: call),
           let calleeEffect = symbolTable.effect(for: calleeSignature),
           calleeEffect == .nonIdempotent {
            let contextLabel: String = site.context == .replayable ? "replayable" : "retry_safe"
            let callerName = site.function.name.text
            let calleeName = calleeSignature.name
            let line = site.locationConverter.location(for: call.positionAfterSkippingLeadingTrivia).line
            addIssue(
                severity: pattern.severity,
                message: "Non-idempotent call in \(contextLabel) context: '\(callerName)' is declared "
                    + "`@lint.context \(contextLabel)` but calls '\(calleeName)', which is declared "
                    + "`@lint.effect non_idempotent`.",
                filePath: site.filePath,
                lineNumber: line,
                suggestion: "Replace '\(calleeName)' with an idempotent alternative, or route the call "
                    + "through a deduplication guard or idempotency-key mechanism.",
                ruleName: .nonIdempotentInRetryContext
            )
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            analyzeBody(child, site: site)
        }
    }

    /// See `IdempotencyViolationVisitor.isEscapingClosure` for the shared policy.
    private func isEscapingClosure(_ closure: ClosureExprSyntax) -> Bool {
        var node = Syntax(closure).parent
        while let current = node {
            if let call = current.as(FunctionCallExprSyntax.self) {
                if let name = directCalleeName(from: call.calledExpression),
                   escapingCalleeNames.contains(name) {
                    return true
                }
                return false
            }
            node = current.parent
        }
        return false
    }

    private func directCalleeName(from expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    private let escapingCalleeNames: Set<String> = [
        "Task",
        "detached",
        "withTaskGroup",
        "withThrowingTaskGroup",
        "withDiscardingTaskGroup",
        "withThrowingDiscardingTaskGroup",
        "task"
    ]
}

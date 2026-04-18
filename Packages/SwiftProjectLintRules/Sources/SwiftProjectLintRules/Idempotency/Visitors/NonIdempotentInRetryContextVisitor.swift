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
        guard let context = EffectAnnotationParser.parseContext(declaration: node),
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
        // Phase-2.3 upward inference — see IdempotencyViolationVisitor for
        // rationale. Runs before the body walk so every lookup in
        // analyzeCall can consult upward-inferred entries. `multiHop: true`
        // enables fixed-point propagation across chains of un-annotated
        // helpers between the `@context replayable` boundary and the
        // non-idempotent leaf.
        let allSources = Array(fileCache.values)
        symbolTable.applyUpwardInference(
            to: allSources,
            multiHop: true,
            heuristicEffectForCall: HeuristicEffectInferrer.infer(call:)
        )

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

        if let call = syntax.as(FunctionCallExprSyntax.self) {
            analyzeCall(call, site: site)
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            analyzeBody(child, site: site)
        }
    }

    /// Resolves the callee's effect via the symbol table, falling back to
    /// Phase-2 heuristic inference for un-annotated callees. Declared effects
    /// always win. Only `non_idempotent` (declared or inferred) fires this
    /// rule; `idempotent`, `observational`, and `externally_idempotent`
    /// callees pass silently in a retry context.
    private func analyzeCall(_ call: FunctionCallExprSyntax, site: AnalysisSite) {
        guard let calleeSignature = FunctionSignature.from(call: call) else { return }

        let calleeEffect: DeclaredEffect
        let calleeClaim: String
        let overrideHint: String

        if let declared = symbolTable.effect(for: calleeSignature) {
            calleeEffect = declared
            calleeClaim = "which is declared `@lint.effect non_idempotent`"
            overrideHint = ""
        } else if symbolTable.isCollision(signature: calleeSignature) {
            // Collision-withdrawn: annotated with conflicting effects. Neither
            // upward nor downward inference runs.
            return
        } else if let upward = symbolTable.upwardInference(for: calleeSignature) {
            calleeEffect = upward.effect
            let chainHint = upward.depth > 1
                ? " via \(upward.depth)-hop chain of un-annotated callees"
                : ""
            calleeClaim = "whose effect is inferred `non_idempotent` from its body\(chainHint)"
            overrideHint = " If the inference is wrong, annotate '\(calleeSignature.name)' "
                + "explicitly with `/// @lint.effect <tier>` to override the body-based inference."
        } else if let inferred = HeuristicEffectInferrer.infer(call: call) {
            calleeEffect = inferred
            let reason = HeuristicEffectInferrer.inferenceReason(for: call) ?? ""
            calleeClaim = "whose effect is inferred `non_idempotent` \(reason)"
            overrideHint = " If the inference is wrong, annotate '\(calleeSignature.name)' "
                + "explicitly with `/// @lint.effect <tier>` to override."
        } else {
            return
        }

        guard calleeEffect == .nonIdempotent else { return }

        let contextLabel: String = site.context == .replayable ? "replayable" : "retry_safe"
        let callerName = site.function.name.text
        let calleeName = calleeSignature.name
        let line = site.locationConverter.location(
            for: call.positionAfterSkippingLeadingTrivia
        ).line

        addIssue(
            severity: pattern.severity,
            message: "Non-idempotent call in \(contextLabel) context: '\(callerName)' is declared "
                + "`@lint.context \(contextLabel)` but calls '\(calleeName)', \(calleeClaim)."
                + overrideHint,
            filePath: site.filePath,
            lineNumber: line,
            suggestion: "Replace '\(calleeName)' with an idempotent alternative, or route the call "
                + "through a deduplication guard or idempotency-key mechanism.",
            ruleName: .nonIdempotentInRetryContext
        )
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

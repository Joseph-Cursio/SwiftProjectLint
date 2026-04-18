import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects functions whose declared effect contract is violated by a call to a
/// more-permissive callee. The resolution is project-wide: callees defined in any
/// file participating in the analysis are resolved against the shared
/// `EffectSymbolTable`, subject to the table's collision policy.
///
/// Two declared-caller effects are analysed:
///
/// - `/// @lint.effect idempotent` — the body must not call a `@lint.effect non_idempotent`
///   callee. Observational and pure callees are acceptable.
/// - `/// @lint.effect observational` — the body must only call observational/pure callees.
///   An idempotent or non_idempotent callee is a violation, because observational claims
///   the body mutates no business state beyond observation sinks.
///
/// ## Cross-file dispatch
/// The visitor conforms to `CrossFilePatternVisitorProtocol`. Walk phase accumulates
/// the symbol table and the list of analysis sites. Emission happens in
/// `finalizeAnalysis()`, once every file has been walked. This keeps the per-file
/// dispatch path a no-op for this rule (no double-emit) while enabling cross-file
/// resolution via the `CrossFileAnalysisEngine`.
///
/// ## Closure traversal policy
/// The visitor descends into non-escaping closure bodies. It does not descend into
/// `ClosureExprSyntax` passed as escaping arguments (`Task { }`, `withTaskGroup { }`,
/// `Task.detached { }`, SwiftUI `.task { }`) — those boundaries are retry-context
/// checks that Phase 1 of the trial explicitly excludes.
final class IdempotencyViolationVisitor: BasePatternVisitor, CrossFilePatternVisitorProtocol {

    let fileCache: [String: SourceFileSyntax]

    /// Accumulated across every file walked in this analysis run. Populated in
    /// `visit(_:)` and queried in `finalizeAnalysis()`.
    private var symbolTable = EffectSymbolTable()

    /// Analysis sites cached during walk, keyed by their declaring file so that
    /// line-number reporting resolves correctly in `finalizeAnalysis()`.
    private var analysisSites: [AnalysisSite] = []

    private struct AnalysisSite {
        let function: FunctionDeclSyntax
        let effect: DeclaredEffect
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

    // MARK: - Walk phase: accumulate only

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        symbolTable.merge(source: node)
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let callerEffect = EffectAnnotationParser.parseEffect(declaration: node),
              callerEffect == .idempotent || callerEffect == .observational,
              node.body != nil else {
            return .visitChildren
        }
        let converter = currentLocationConverter
            ?? SourceLocationConverter(fileName: currentFilePath, tree: node.root)
        analysisSites.append(
            AnalysisSite(
                function: node,
                effect: callerEffect,
                filePath: currentFilePath,
                locationConverter: converter
            )
        )
        return .visitChildren
    }

    // MARK: - Finalize phase: emit issues

    func finalizeAnalysis() {
        for site in analysisSites {
            guard let body = site.function.body else { continue }
            analyzeBody(Syntax(body), site: site)
        }
    }

    /// Single-file fallback: when the visitor is used outside the cross-file engine
    /// (for example directly in unit tests), callers can walk once and invoke this
    /// method instead of `finalizeAnalysis()` — they are equivalent. Exposed as a
    /// separate name to make the test flow read `walk(source); analyze()`.
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
           violates(caller: site.effect, callee: calleeEffect) {
            emitViolation(
                call: call,
                site: site,
                calleeName: calleeSignature.name,
                calleeEffect: calleeEffect
            )
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            analyzeBody(child, site: site)
        }
    }

    /// Effect-conflict rules for Phase 1. Only direct declared-vs-declared mismatches
    /// fire; unannotated callees stay silent (Phase 1 does not infer).
    private func violates(caller: DeclaredEffect, callee: DeclaredEffect) -> Bool {
        switch (caller, callee) {
        case (.idempotent, .nonIdempotent):
            return true
        case (.observational, .nonIdempotent):
            return true
        case (.observational, .idempotent):
            return true
        default:
            return false
        }
    }

    private func emitViolation(
        call: FunctionCallExprSyntax,
        site: AnalysisSite,
        calleeName: String,
        calleeEffect: DeclaredEffect
    ) {
        let callerName = site.function.name.text
        let callerTier = effectLabel(site.effect)
        let calleeTier = effectLabel(calleeEffect)
        let headline: String
        let suggestion: String
        switch site.effect {
        case .observational:
            headline = "Observational contract violation: '\(callerName)' is declared "
                + "`@lint.effect observational` but calls '\(calleeName)', which is declared "
                + "`@lint.effect \(calleeTier)`. Observational functions must not mutate "
                + "business state beyond observation sinks."
            suggestion = "Either call only observational/pure helpers from '\(callerName)', "
                + "or weaken its declared effect to `idempotent` / `non_idempotent`."
        case .idempotent:
            headline = "Idempotency violation: '\(callerName)' is declared "
                + "`@lint.effect \(callerTier)` but calls '\(calleeName)', which is declared "
                + "`@lint.effect \(calleeTier)`."
            suggestion = "Either change '\(calleeName)' to an idempotent alternative "
                + "(e.g. upsert, set-status-by-id), or weaken the declared effect of '\(callerName)'."
        default:
            return
        }
        let line = site.locationConverter.location(for: call.positionAfterSkippingLeadingTrivia).line
        addIssue(
            severity: pattern.severity,
            message: headline,
            filePath: site.filePath,
            lineNumber: line,
            suggestion: suggestion,
            ruleName: .idempotencyViolation
        )
    }

    private func effectLabel(_ effect: DeclaredEffect) -> String {
        switch effect {
        case .idempotent: return "idempotent"
        case .observational: return "observational"
        case .nonIdempotent: return "non_idempotent"
        }
    }

    /// A closure is treated as escaping when it is the trailing closure of a call
    /// whose callee is in `escapingCalleeNames`. Matching happens on the *nearest*
    /// enclosing `FunctionCallExprSyntax`; a closure deeply nested inside a
    /// non-escaping call is treated as non-escaping relative to the Phase 1 body
    /// check. The visitor's Phase 1 scope stops at these boundaries.
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

    /// Callees whose trailing closures are treated as escaping for Phase 1 purposes.
    /// `task` is deliberately included so that SwiftUI's `.task { … }` modifier
    /// boundary is honoured — the SwiftUI runtime re-runs the closure on view
    /// identity changes, so it's a genuine replay boundary, not part of the
    /// caller's synchronous body.
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

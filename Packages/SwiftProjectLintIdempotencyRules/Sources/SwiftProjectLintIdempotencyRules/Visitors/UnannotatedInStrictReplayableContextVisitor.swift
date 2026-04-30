import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects functions declared `/// @lint.context strict_replayable` whose
/// body calls a function whose effect cannot be proven. The "strict" in
/// `strict_replayable` flips the default for unannotated callees — under
/// `replayable`, unannotated callees are silent; under
/// `strict_replayable`, they fire this rule.
///
/// ## Firing condition
///
/// A callee fires the rule iff **none** of the following hold:
///
///   - Declared effect via the symbol table (any tier — even
///     `non_idempotent` defers, because `nonIdempotentInRetryContext`
///     already fires on that).
///   - Upward-inferred effect (any tier, same rationale).
///   - Heuristic effect inference returned a classification — either
///     `nonIdempotent` (existing rule handles) or a positive tier
///     (trusted as a prove-enough signal for strict mode, matching the
///     round-5/6 precision profile).
///   - Symbol-table collision (annotated with conflicting effects; no
///     inference runs; no double-diagnostic).
///
/// Only callees that reach the fall-through "no evidence" branch fire
/// this rule. That's the whole gap strict mode closes.
///
/// ## Relationship to `nonIdempotentInRetryContext`
///
/// This rule does not replicate the existing rule's diagnostic on
/// `non_idempotent` callees in a strict_replayable body — that firing
/// comes from the existing rule, which already treats
/// `strict_replayable` as a retry-context caller (identical label
/// plumbing). Strict mode only *adds* the unannotated-callee case.
///
/// Round-9 / phase-2 strict-replayable slice. See
/// `docs/claude_phase_2_strict_replayable_plan.md`.
final class UnannotatedInStrictReplayableContextVisitor:
    BasePatternVisitor, CrossFilePatternVisitorProtocol {

    let fileCache: [String: SourceFileSyntax]

    private var symbolTable = EffectSymbolTable()
    private var analysisSites: [AnalysisSite] = []

    private struct AnalysisSite {
        let callerName: String
        let body: Syntax
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
        guard ContextAnnotationParser.parseContext(declaration: node) == .strictReplayable,
              let body = node.body else {
            return .visitChildren
        }
        let converter = currentLocationConverter
            ?? SourceLocationConverter(fileName: currentFilePath, tree: node.root)
        analysisSites.append(
            AnalysisSite(
                callerName: node.name.text,
                body: Syntax(body),
                filePath: currentFilePath,
                locationConverter: converter
            )
        )
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard ContextAnnotationParser.parseContext(declaration: node) == .strictReplayable,
              let closure = node.closureInitializer,
              let name = node.firstBindingName else {
            return .visitChildren
        }
        let converter = currentLocationConverter
            ?? SourceLocationConverter(fileName: currentFilePath, tree: node.root)
        analysisSites.append(
            AnalysisSite(
                callerName: name,
                body: Syntax(closure.statements),
                filePath: currentFilePath,
                locationConverter: converter
            )
        )
        return .visitChildren
    }

    /// Trailing-closure annotation (round-11 grammar extension). An
    /// un-bound closure passed to a call with `/// @lint.context
    /// strict_replayable` above it becomes an analysis site. Matches the
    /// pattern in `NonIdempotentInRetryContextVisitor.visit(_:)`; see
    /// that visitor's doc comment for the shape rationale and the TCA
    /// adopter round for the prefix-statement gap this helper closes.
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard ContextAnnotationParser.parseContextAtCallSite(of: node)
                == .strictReplayable,
              let closure = node.trailingClosure else {
            return .visitChildren
        }
        let converter = currentLocationConverter
            ?? SourceLocationConverter(fileName: currentFilePath, tree: node.root)
        analysisSites.append(
            AnalysisSite(
                callerName: "closure",
                body: Syntax(closure.statements),
                filePath: currentFilePath,
                locationConverter: converter
            )
        )
        return .visitChildren
    }

    func finalizeAnalysis() {
        let allSources = Array(fileCache.values)
        let enabledFrameworks = self.enabledFrameworkWhitelists
        symbolTable.applyUpwardInferenceImportAware(
            to: allSources,
            multiHop: true,
            heuristicEffectForCall: { call, source in
                CallSiteEffectInferrer.infer(
                    call: call,
                    imports: ImportCollector.imports(in: source),
                    enabledFrameworks: enabledFrameworks
                )
            }
        )

        for site in analysisSites {
            analyzeBody(site.body, site: site)
        }
    }

    func analyze() {
        finalizeAnalysis()
    }

    private func analyzeBody(_ syntax: Syntax, site: AnalysisSite) {
        if syntax.is(FunctionDeclSyntax.self) { return }
        // Nested closure-initialised variable bindings that carry their
        // own `@lint.context` annotation are independent analysis sites;
        // don't descend.
        if let varDecl = syntax.as(VariableDeclSyntax.self),
           varDecl.closureInitializer != nil,
           ContextAnnotationParser.parseContext(declaration: varDecl) != nil {
            return
        }
        // Same rule for annotated trailing-closure sites (round-11). Use
        // the call-site variant so prefix-statement annotations don't get
        // double-walked — see NonIdempotentInRetryContextVisitor's matching
        // guard.
        if let call = syntax.as(FunctionCallExprSyntax.self),
           call.trailingClosure != nil,
           ContextAnnotationParser.parseContextAtCallSite(of: call) != nil {
            return
        }
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

    private func analyzeCall(_ call: FunctionCallExprSyntax, site: AnalysisSite) {
        guard let calleeSignature = FunctionSignature.from(call: call) else { return }

        // Structural-concurrency and SwiftUI task primitives — `Task { ... }`,
        // `Task.detached { ... }`, `withTaskGroup`, `.task { }`, etc. These
        // aren't effect-bearing calls; they're scoping primitives. The
        // existing rule filters them implicitly because it only fires on
        // declared/inferred `non_idempotent`; strict mode needs an
        // explicit exclusion or it fires on every `Task { }` in a
        // strict-replayable body.
        if let bareName = directCalleeName(from: call.calledExpression),
           escapingCalleeNames.contains(bareName) {
            return
        }

        // Any declared effect — even non_idempotent — means the callee is
        // classified. `nonIdempotentInRetryContext` handles the negative
        // case; positive tiers pass silently.
        if symbolTable.effect(for: calleeSignature) != nil { return }

        // Collision-withdrawn: do not double-fire.
        if symbolTable.isCollision(signature: calleeSignature) { return }

        // Upward-inferred classification (from sub-graph analysis) also
        // counts as "proven" for strict-mode purposes.
        if symbolTable.upwardInference(for: calleeSignature) != nil { return }

        // Heuristic inferrer returning any classification counts — either
        // the existing rule handles it, or it's a positive signal.
        if CallSiteEffectInferrer.infer(
            call: call,
            imports: imports(forSiteFile: site.filePath),
            enabledFrameworks: self.enabledFrameworkWhitelists
        ) != nil { return }

        // Fall through: no evidence of the callee's effect. Fire.
        let callerName = site.callerName
        let calleeName = calleeSignature.name
        let line = site.locationConverter.location(
            for: call.positionAfterSkippingLeadingTrivia
        ).line

        addIssue(
            severity: pattern.severity,
            message: "Unannotated call in strict_replayable context: '\(callerName)' is "
                + "declared `@lint.context strict_replayable` but calls '\(calleeName)', "
                + "whose effect is not declared and cannot be inferred from its body. "
                + "Under strict mode, every callee must be provably idempotent, "
                + "observational, or externally-keyed.",
            filePath: site.filePath,
            lineNumber: line,
            suggestion: "Annotate '\(calleeName)' with `/// @lint.effect idempotent` if "
                + "re-invocation produces no additional observable effects; `observational` "
                + "for logging/metrics/tracing primitives; `externally_idempotent(by: <param>)` "
                + "for calls routed through a caller-supplied deduplication key. Or use the "
                + "attribute forms (`@Idempotent`, `@Observational`, "
                + "`@ExternallyIdempotent(by:)`) from the `SwiftIdempotency` macros package.",
            ruleName: .unannotatedInStrictReplayableContext
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

    /// Per-file imports cache. See `NonIdempotentInRetryContextVisitor.imports(forSiteFile:)`.
    private func imports(forSiteFile path: String) -> Set<String> {
        if let cached = importCache[path] { return cached }
        guard let source = fileCache[path] else { return [] }
        let set = ImportCollector.imports(in: source)
        importCache[path] = set
        return set
    }

    private var importCache: [String: Set<String>] = [:]
}

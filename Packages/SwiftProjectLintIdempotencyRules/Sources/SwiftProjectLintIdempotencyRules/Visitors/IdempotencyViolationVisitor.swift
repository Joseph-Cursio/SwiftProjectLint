import SwiftEffectInference
import SwiftProjectLintModels
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
final class IdempotencyViolationVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// The run's declared and upward-inferred effects, read from `ProjectEffectTables` in
    /// `finalizeAnalysis()`.
    private var symbolTable = EffectSymbolTable()

    /// Files walked, for the tables a directly driven visitor builds itself. A run's engine hands
    /// over `sharedEffectTables` instead, and then nothing is kept here.
    private var walkedSources: [SourceFileSyntax] = []

    /// Analysis sites cached during walk, keyed by their declaring file so that
    /// line-number reporting resolves correctly in `finalizeAnalysis()`.
    private var analysisSites: [AnalysisSite] = []

    /// A location in source that carries a `@lint.effect` annotation and
    /// whose body the rule will walk. Uniformly represents both function
    /// declarations and closure-initialised variable bindings.
    struct AnalysisSite {
        let callerName: String
        let body: Syntax
        let effect: DeclaredEffect
        let location: CapturedSiteLocation
        /// What would have to widen for a test to call `callerName`, or `nil` if nothing does.
        ///
        /// Captured here, from the declaration itself, rather than recomputed at emit time from
        /// `body`: a closure site's body is the closure's statements, whose parent is a
        /// `ClosureExprSyntax` and not a declaration, so the `private let` binding that carries the
        /// annotation would go unnoticed. The declaration is in hand at capture; keep it.
        let restriction: TestRestriction?
    }

    // MARK: - Walk phase: accumulate only

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        if sharedEffectTables == nil { walkedSources.append(node) }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let callerEffect = EffectAnnotationParser.parseEffect(declaration: node),
              isTriageableCaller(callerEffect),
              let body = node.body else {
            return .visitChildren
        }
        analysisSites.append(
            AnalysisSite(
                callerName: node.name.text,
                body: Syntax(body),
                effect: callerEffect,
                location: captureSiteLocation(rootedAt: node),
                restriction: PropertyTestCandidacy.restriction(of: node)
            )
        )
        return .visitChildren
    }

    /// Closure-binding annotation (Phase 2 third slice). A `let`/`var` with
    /// a closure-literal initialiser and a `@lint.effect` annotation is
    /// treated analogously to an annotated function: the closure's body is
    /// walked under the declared effect and any violating call fires the
    /// rule. Only triageable caller effects (`idempotent`, `observational`,
    /// `externallyIdempotent`) collect a site.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let callerEffect = EffectAnnotationParser.parseEffect(declaration: node),
              isTriageableCaller(callerEffect),
              let closure = node.closureInitializer,
              let name = node.firstBindingName else {
            return .visitChildren
        }
        analysisSites.append(
            AnalysisSite(
                callerName: name,
                body: Syntax(closure.statements),
                effect: callerEffect,
                location: captureSiteLocation(rootedAt: node),
                restriction: PropertyTestCandidacy.restriction(of: node)
            )
        )
        return .visitChildren
    }

    // MARK: - Finalize phase: emit issues

    func finalizeAnalysis() {
        symbolTable = effectTables(walked: walkedSources).inferred

        for site in analysisSites {
            analyzeBody(site.body, site: site)
        }
    }

    private func analyzeBody(_ syntax: Syntax, site: AnalysisSite) {
        AnalysisBodyWalk.walk(syntax, skipping: carriesOwnEffectAnnotation) { call in
            analyzeCall(call, site: site)
        }
    }

    /// Nested closure-initialised variable bindings that carry their own
    /// `@lint.effect` annotation are independent analysis sites. Don't descend
    /// — calls inside would otherwise be attributed to the outer effect.
    /// Unannotated closure-bound bindings keep the old behaviour: they inherit
    /// the outer site's effect and are walked through.
    func carriesOwnEffectAnnotation(_ syntax: Syntax) -> Bool {
        guard let varDecl = syntax.as(VariableDeclSyntax.self),
              varDecl.closureInitializer != nil else {
            return false
        }
        return EffectAnnotationParser.parseEffect(declaration: varDecl) != nil
    }

    /// Resolves a call's callee effect via the symbol table, falling back to
    /// Phase-2 heuristic inference when no declared effect is found. Declared
    /// effects always win; inference is strictly a fallback for the
    /// un-annotated case.
    private func analyzeCall(_ call: FunctionCallExprSyntax, site: AnalysisSite) {
        guard let calleeSignature = FunctionSignature.from(call: call) else { return }

        let calleeEffect: DeclaredEffect
        let provenance: EffectProvenance

        // The lookup is by *call shape*, not bare signature: Swift drops a trailing closure's
        // argument label, so `perform { }` against `func perform(action:)` cannot be found
        // by name alone — and Swift is made of trailing closures.
        let calleeCall = CallSiteShape.from(call: call) ?? CallSiteShape(signature: calleeSignature)

        if let declared = symbolTable.effect(for: calleeCall) {
            calleeEffect = declared
            provenance = .declared
        } else if symbolTable.isCollision(signature: calleeSignature) {
            // Collision-withdrawn: the user annotated this callee more than
            // once with conflicting effects. Neither upward nor heuristic
            // inference runs — a guess would substitute a third
            // interpretation the user did not ask for. Stay silent.
            return
        } else if let upward = symbolTable.upwardInference(for: calleeSignature) {
            calleeEffect = upward.effect
            provenance = .inferredUpward(depth: upward.depth, anchor: upward.anchor)
        } else if let inferred = HeuristicEffectInferrer.infer(
            call: call,
            imports: siteImportCache.imports(forSiteFile: site.location.filePath),
            enabledFrameworks: self.enabledFrameworkAllowlists
        ) {
            calleeEffect = inferred
            provenance = .inferredDownward(
                reason: HeuristicEffectInferrer.inferenceReason(
                    for: call,
                    imports: siteImportCache.imports(forSiteFile: site.location.filePath),
                    enabledFrameworks: self.enabledFrameworkAllowlists
                ) ?? ""
            )
        } else {
            return
        }

        guard violates(caller: site.effect, callee: calleeEffect) else { return }

        emitViolation(
            call: call,
            site: site,
            calleeName: calleeSignature.name,
            calleeEffect: calleeEffect,
            provenance: provenance
        )
    }

    /// Tracks where an effect came from. The distinction surfaces in
    /// diagnostic prose so users know what signal the rule is acting on
    /// and how to override.
    ///
    /// - `declared`: `@lint.effect` annotation on the callee.
    /// - `inferredUpward(depth:)`: computed from the callee's own body
    ///   (Phase 2.3). `depth: 1` is single-pass / one-hop; `depth: 2+` is
    ///   multi-hop (a chain of un-annotated callees, surfaced in the
    ///   diagnostic so users can locate the chain).
    /// - `inferredDownward`: computed from the call-site syntax (callee name
    ///   or receiver name, Phase 2.2).
    enum EffectProvenance {
        case declared
        case inferredUpward(depth: Int, anchor: BodyInference.Anchor)
        case inferredDownward(reason: String)
    }

    /// Per-file imports cache shared with the other idempotency visitors.
    private lazy var siteImportCache = SiteImportCache(fileCache: fileCache)
}

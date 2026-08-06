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

    /// Accumulated across every file walked in this analysis run. Populated in
    /// `visit(_:)` and queried in `finalizeAnalysis()`.
    private var symbolTable = EffectSymbolTable()

    /// Analysis sites cached during walk, keyed by their declaring file so that
    /// line-number reporting resolves correctly in `finalizeAnalysis()`.
    private var analysisSites: [AnalysisSite] = []

    /// A location in source that carries a `@lint.effect` annotation and
    /// whose body the rule will walk. Uniformly represents both function
    /// declarations and closure-initialised variable bindings.
    private struct AnalysisSite {
        let callerName: String
        let body: Syntax
        let effect: DeclaredEffect
        let location: CapturedSiteLocation
    }

    // MARK: - Walk phase: accumulate only

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        symbolTable.merge(source: node)
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
                location: captureSiteLocation(rootedAt: node)
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
                location: captureSiteLocation(rootedAt: node)
            )
        )
        return .visitChildren
    }

    // MARK: - Finalize phase: emit issues

    func finalizeAnalysis() {
        // Phase-2.3: after all files have merged declared effects into the
        // symbol table, run body-based upward inference. Must happen here
        // (not during walk) because upward inference uses cross-file
        // declared effects and heuristic-downward resolution, both of which
        // are only complete at finalize time.
        //
        // `multiHop: true` enables fixed-point propagation across chains
        // of un-annotated functions. A function whose body calls another
        // un-annotated function whose own body has a non-idempotent leaf
        // is now inferred non-idempotent itself. One-hop catches only the
        // direct caller of the leaf.
        let allSources = Array(fileCache.values)
        let enabledFrameworks = self.enabledFrameworkAllowlists
        symbolTable.applyBodyInference(to: allSources, multiHop: true) { call, source in
            HeuristicEffectInferrer.infer(
                call: call,
                imports: SwiftProjectLintVisitors.ImportCollector.imports(in: source),
                enabledFrameworks: enabledFrameworks
            )
        }

        for site in analysisSites {
            analyzeBody(site.body, site: site)
        }
    }

    private func analyzeBody(_ syntax: Syntax, site: AnalysisSite) {
        if syntax.is(FunctionDeclSyntax.self) { return }
        // Nested closure-initialised variable bindings that carry their
        // own `@lint.effect` annotation are independent analysis sites.
        // Don't descend — calls inside would otherwise be attributed to
        // the outer effect. Unannotated closure-bound bindings keep the
        // old behaviour: they inherit the outer site's effect and are
        // walked through.
        if let varDecl = syntax.as(VariableDeclSyntax.self),
           varDecl.closureInitializer != nil,
           EffectAnnotationParser.parseEffect(declaration: varDecl) != nil {
            return
        }
        if let closure = syntax.as(ClosureExprSyntax.self), EscapingClosurePolicy.isEscaping(closure) {
            return
        }

        if let call = syntax.as(FunctionCallExprSyntax.self) {
            analyzeCall(call, site: site)
        }

        for child in syntax.children(viewMode: .sourceAccurate) {
            analyzeBody(child, site: site)
        }
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
    private enum EffectProvenance {
        case declared
        case inferredUpward(depth: Int, anchor: BodyInference.Anchor)
        case inferredDownward(reason: String)
    }

    /// Caller effects whose bodies are analysed by this rule. `nonIdempotent`
    /// is excluded — a non-idempotent caller makes no stronger claim than its
    /// callees, so there is nothing to violate.
    private func isTriageableCaller(_ effect: DeclaredEffect) -> Bool {
        switch effect {
        case .pure, .idempotent, .observational, .externallyIdempotent: return true
        case .nonIdempotent: return false
        }
    }

    /// Effect-conflict rules. Only direct declared-vs-declared mismatches fire;
    /// unannotated callees stay silent (Phase 1 does not infer).
    ///
    /// Phase 2 added `externally_idempotent` rows:
    ///
    /// - `idempotent → externally_idempotent`: **OK by default.** The caller
    ///   is trusted to route a deduplication key through. Verifying the key
    ///   actually reaches the callee is deferred to a follow-up rule
    ///   (`missingIdempotencyKey`).
    /// - `observational → externally_idempotent`: **violation.** External
    ///   operations unconditionally mutate business state — even with a key,
    ///   a Stripe charge is not an observation. The observational contract
    ///   forbids this regardless of key routing.
    /// - `externally_idempotent → non_idempotent`: **violation.** Any
    ///   unconditionally non-idempotent work inside a keyed operation
    ///   re-fires on replay regardless of the caller's idempotency key, so
    ///   the keyed guarantee is broken.
    /// - `externally_idempotent → idempotent / observational / externally_idempotent`:
    ///   **OK.** Composition holds.
    ///
    /// Phase 3 added the `pure` caller rows. `pure` is the lattice bottom —
    /// referential transparency — so a function declared `@lint.effect pure`
    /// may call *only* other pure functions. Any callee at a higher tier
    /// (`observational` and up) introduces a side effect or an observation the
    /// pure contract forbids, so every `pure → non-pure` pairing violates.
    private func violates(caller: DeclaredEffect, callee: DeclaredEffect) -> Bool {
        switch (caller, callee) {
        // Phase 3: a pure caller may call only pure callees; anything else
        // (observational/idempotent/externallyIdempotent/nonIdempotent) breaks
        // referential transparency.
        case (.pure, .pure):
            return false

        case (.pure, _):
            return true

        // Phase 1 cases
        case (.idempotent, .nonIdempotent):
            return true

        case (.observational, .nonIdempotent):
            return true

        case (.observational, .idempotent):
            return true

        // Phase 2 cases (externally_idempotent tier); `_` ignores the
        // associated `keyParameter` — lattice rows fire on tier alone.
        case (.observational, .externallyIdempotent):
            return true

        case (.externallyIdempotent, .nonIdempotent):
            return true

        default:
            return false
        }
    }

    private func emitViolation(
        call: FunctionCallExprSyntax,
        site: AnalysisSite,
        calleeName: String,
        calleeEffect: DeclaredEffect,
        provenance: EffectProvenance
    ) {
        let callerName = site.callerName
        let callerTier = effectLabel(site.effect)
        let calleeTier = effectLabel(calleeEffect)
        // Two prose fragments covering the same semantic point: the callee's
        // effect is `calleeTier`. Declared is authoritative; inferred credits
        // the heuristic and tells the user how to override.
        let calleeClaim: String
        let overrideHint: String
        switch provenance {
        case .declared:
            calleeClaim = "which is declared `@lint.effect \(calleeTier)`"
            overrideHint = ""

        case .inferredUpward(let depth, let chainAnchor):
            let chainHint = depth > 1 ? " via \(depth)-hop chain of un-annotated callees" : ""
            // Say what the chain bottoms out on. A reader deciding whether to
            // trust a multi-hop inference is asking exactly this, and until the
            // anchor was tracked the diagnostic could not answer: a chain
            // resting entirely on annotations and one resting on a name match
            // read identically.
            let anchorHint = chainAnchor == .declared
                ? ", resting on a declared effect"
                : ", resting on a name-based guess"
            calleeClaim = "whose effect is inferred `\(calleeTier)` from its body"
                + "\(chainHint)\(anchorHint)"
            overrideHint = " If the inference is wrong, annotate '\(calleeName)' "
                + "explicitly with `/// @lint.effect <tier>` to override the body-based inference."

        case .inferredDownward(let reason):
            calleeClaim = "whose effect is inferred `\(calleeTier)` \(reason)"
            overrideHint = " If the inference is wrong, annotate '\(calleeName)' "
                + "explicitly with `/// @lint.effect <tier>` to override."
        }

        let headline: String
        let suggestion: String
        switch site.effect {
        case .pure:
            headline = "Purity violation: '\(callerName)' is declared "
                + "`@lint.effect pure` but calls '\(calleeName)', \(calleeClaim). "
                + "A pure function must be referentially transparent — no side effects, no I/O, "
                + "no observation — so it may call only other pure functions."
                + overrideHint
            suggestion = "Either call only `pure` helpers from '\(callerName)', or weaken its "
                + "declared effect to `observational` / `idempotent` / `non_idempotent`."

        case .observational:
            headline = "Observational contract violation: '\(callerName)' is declared "
                + "`@lint.effect observational` but calls '\(calleeName)', \(calleeClaim). "
                + "Observational functions must not mutate business state beyond observation sinks."
                + overrideHint
            suggestion = "Either call only observational/pure helpers from '\(callerName)', "
                + "or weaken its declared effect to `idempotent` / `non_idempotent`."

        case .idempotent:
            headline = "Idempotency violation: '\(callerName)' is declared "
                + "`@lint.effect \(callerTier)` but calls '\(calleeName)', \(calleeClaim)."
                + overrideHint
            suggestion = "Either change '\(calleeName)' to an idempotent alternative "
                + "(e.g. upsert, set-status-by-id), or weaken the declared effect of '\(callerName)'."

        case .externallyIdempotent:
            headline = "Externally-idempotent contract violation: '\(callerName)' is declared "
                + "`@lint.effect externally_idempotent` but calls '\(calleeName)', \(calleeClaim). "
                + "An externally-idempotent operation's keyed guarantee is only as strong as its "
                + "weakest uninstrumented call — any unconditionally non-idempotent work inside "
                + "the body re-fires on replay regardless of the caller's idempotency key."
                + overrideHint
            suggestion = "Route '\(calleeName)' through its own idempotency key, replace it "
                + "with an idempotent alternative, or weaken '\(callerName)' to "
                + "`@lint.effect non_idempotent`."

        default:
            return
        }
        let line = site.location.line(of: call)
        addIssue(
            severity: pattern.severity,
            message: headline,
            filePath: site.location.filePath,
            lineNumber: line,
            suggestion: suggestion,
            ruleName: .idempotencyViolation,
            // The violating function is itself the idempotence property-test
            // subject — surfaced as a seed for `--format pbt-seeds`.
            symbol: callerName,
            // …and the lattice position it was judged on travels with it. The
            // seed already said *that* the claim failed; this says what was
            // claimed, what the body reached, and how confidently the rule
            // knows — the last of which no consumer can recompute, because the
            // resolution is cross-file and multi-hop.
            effect: seedEffect(callerEffect: site.effect, calleeEffect: calleeEffect, provenance: provenance)
        )
    }

    /// Project the rule's own effect vocabulary onto the manifest's.
    ///
    /// A deliberate translation rather than a shared type. `DeclaredEffect` is
    /// SwiftEffectInference's enum and `EffectProvenance` is private to this
    /// visitor; making either one Codable to save this function would put the
    /// manifest's wire format at the mercy of a rename in a dependency, and the
    /// manifest is a published contract with a version number. The exhaustive
    /// switches are the point: adding a tier upstream should fail to compile
    /// here rather than silently emit a case a consumer has never seen.
    private func seedEffect(
        callerEffect: DeclaredEffect,
        calleeEffect: DeclaredEffect,
        provenance: EffectProvenance
    ) -> PBTSeedEffect {
        let depth: Int?
        let reason: String?
        // `nil` for the two provenances where the question does not arise: a
        // declaration IS the anchor, and a heuristic match is a guess by
        // construction. Only an upward chain has a bottom worth naming.
        let anchor: PBTSeedEffect.Anchor?
        let wireProvenance: PBTSeedEffect.Provenance
        switch provenance {
        case .declared:
            wireProvenance = .declared
            depth = nil
            anchor = nil
            reason = nil

        case let .inferredUpward(hops, chainAnchor):
            wireProvenance = .inferredUpward
            depth = hops
            // Carried so a consumer can tell a chain of annotations from one
            // that bottomed out on a name match. Without it, `inferred-upward`
            // is honest but unusable: SwiftInferProperties withheld every one,
            // because this visitor supplies `HeuristicEffectInferrer` as the
            // anchor resolver and provenance alone describes only the last hop.
            anchor = chainAnchor == .declared ? .declaration : .heuristic
            reason = nil

        case let .inferredDownward(why):
            wireProvenance = .inferredDownward
            depth = nil
            anchor = nil
            // The heuristic inferrer returns "" when it matched but could not
            // phrase why. Empty is not a reason, and a consumer rendering it
            // would print a dangling "because ." — `nil` says the same thing
            // honestly.
            reason = why.isEmpty ? nil : why
        }
        return PBTSeedEffect(
            declared: seedTier(callerEffect),
            resolved: seedTier(calleeEffect),
            provenance: wireProvenance,
            depth: depth,
            anchor: anchor,
            reason: reason
        )
    }

    /// Lattice position → wire spelling. Mirrors `effectLabel`, which produces
    /// the same tokens for human prose; both exist because one is a `String` for
    /// a sentence and the other is a typed case in a published schema, and
    /// collapsing them would let a reworded diagnostic change the manifest.
    private func seedTier(_ effect: DeclaredEffect) -> PBTSeedEffect.Tier {
        switch effect {
        case .pure: return .pure
        case .idempotent: return .idempotent
        case .observational: return .observational
        case .externallyIdempotent: return .externallyIdempotent
        case .nonIdempotent: return .nonIdempotent
        }
    }

    private func effectLabel(_ effect: DeclaredEffect) -> String {
        switch effect {
        case .pure: return "pure"
        case .idempotent: return "idempotent"
        case .observational: return "observational"
        case .externallyIdempotent: return "externally_idempotent"   // tier-only label; (by:) is a visitor-level detail
        case .nonIdempotent: return "non_idempotent"
        }
    }

    /// Per-file imports cache shared with the other idempotency visitors.
    private lazy var siteImportCache = SiteImportCache(fileCache: fileCache)
}

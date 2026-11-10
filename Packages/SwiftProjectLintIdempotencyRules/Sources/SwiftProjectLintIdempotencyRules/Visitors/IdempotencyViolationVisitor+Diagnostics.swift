import SwiftEffectInference
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

extension IdempotencyViolationVisitor {
    /// Caller effects whose bodies are analysed by this rule. `nonIdempotent`
    /// is excluded — a non-idempotent caller makes no stronger claim than its
    /// callees, so there is nothing to violate.
    func isTriageableCaller(_ effect: DeclaredEffect) -> Bool {
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
    func violates(caller: DeclaredEffect, callee: DeclaredEffect) -> Bool {
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

    /// Two prose fragments covering the same semantic point: the callee's effect is
    /// `calleeTier`. Declared is authoritative; inferred credits the heuristic and tells the
    /// user how to override.
    private static func calleeProse(
        provenance: EffectProvenance,
        calleeTier: String,
        calleeName: String
    ) -> (claim: String, overrideHint: String) {
        let calleeClaim: String
        let overrideHint: String
        switch provenance {
        case .declared:
            calleeClaim = "which is declared `@lint.effect \(calleeTier)`"
            overrideHint = ""

        case let .inferredUpward(depth, chainAnchor):
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
        return (calleeClaim, overrideHint)
    }

    /// The diagnostic's headline and suggestion for a caller declared `effect` that calls a
    /// callee described by `calleeProse`; `nil` for an effect with no contract to break.
    private static func contractProse(
        for effect: DeclaredEffect,
        callerName: String,
        callerTier: String,
        calleeName: String,
        calleeProse: (claim: String, overrideHint: String)
    ) -> (headline: String, suggestion: String)? {
        let headline: String
        let suggestion: String
        let (calleeClaim, overrideHint) = calleeProse
        switch effect {
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
            return nil
        }
        return (headline, suggestion)
    }

    func emitViolation(
        call: FunctionCallExprSyntax,
        site: AnalysisSite,
        calleeName: String,
        calleeEffect: DeclaredEffect,
        provenance: EffectProvenance
    ) {
        let callerName = site.callerName
        let callerTier = effectLabel(site.effect)
        let calleeTier = effectLabel(calleeEffect)
        let (calleeClaim, overrideHint) = Self.calleeProse(
            provenance: provenance, calleeTier: calleeTier, calleeName: calleeName
        )

        guard let (headline, suggestion) = Self.contractProse(
            for: site.effect,
            callerName: callerName,
            callerTier: callerTier,
            calleeName: calleeName,
            calleeProse: (calleeClaim, overrideHint)
        ) else { return }
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
            effect: seedEffect(callerEffect: site.effect, calleeEffect: calleeEffect, provenance: provenance),
            // Whether a test can reach the symbol above, so the export layer can demote an
            // otherwise-analysable seed to `restricted-function`. Without this the demotion was
            // reachable only from `pureFunctionCandidate`, the one visitor that computed it, and
            // an idempotency seed naming a `private` function was handed over as analysable — a
            // subject the consumer cannot call. `.idempotency` is an analysable kind, so the
            // demotion path is live here; the kernel rules are excluded by `effectiveKind` for a
            // different reason and correctly leave this `.unknown`.
            testReachability: site.restriction.map(TestReachability.unreachable) ?? .reachable
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
}

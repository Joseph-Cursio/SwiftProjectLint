import Core
import Foundation
import Testing

/// The effect tier crossing the manifest boundary.
///
/// `PBTSeedKind.idempotency` says a symbol violated its claim. It does not say
/// what was claimed, what the body reached, or how confidently the linter knows
/// — and SwiftInferProperties named that gap from the other side, observing that
/// this linter resolves effects cross-file and multi-hop while *"none of that
/// crosses into `.pbt/seeds.json`, which carries the idempotency violation but
/// not the tier."*
///
/// The valuable half is `resolved`, not `declared`: a consumer parsing the same
/// source can read the annotation itself, but cannot reproduce a multi-hop
/// resolution of what the body actually reaches.
@Suite("PBT seeds — the effect tier and its provenance")
struct PBTSeedEffectTests {

    // MARK: - Helpers

    private func violation(
        symbol: String = "confirmOrder",
        effect: PBTSeedEffect?
    ) -> LintIssue {
        LintIssue(
            severity: .error,
            message: "`\(symbol)` claims idempotence but calls non-idempotent work",
            filePath: "Orders.swift",
            lineNumber: 11,
            suggestion: "Route it through an idempotency key",
            ruleName: .idempotencyViolation,
            symbol: symbol,
            effect: effect
        )
    }

    private func decodedSeeds(_ issues: [LintIssue]) throws -> [PBTSeed] {
        let json = PBTSeedsFormatter().format(issues: issues)
        let data = try #require(json.data(using: .utf8))
        return try JSONDecoder().decode(PBTSeedManifest.self, from: data).seeds
    }

    // MARK: - The tier reaches the manifest

    @Test("a violation seed carries the claimed and resolved tiers")
    func carriesBothTiers() throws {
        let seeds = try decodedSeeds([
            violation(effect: PBTSeedEffect(
                declared: .idempotent, resolved: .nonIdempotent, provenance: .declared
            ))
        ])
        let effect = try #require(seeds.first?.effect)
        #expect(effect.declared == .idempotent)
        #expect(effect.resolved == .nonIdempotent)
        #expect(effect.provenance == .declared)
    }

    /// Depth is confidence, not decoration: `depth: 1` means every contributing
    /// callee was itself annotated, `depth: 4` means the tier survived three
    /// functions nobody annotated. A consumer weighting by confidence has no
    /// other signal to weight on.
    @Test("an upward inference carries its hop count")
    func upwardCarriesDepth() throws {
        let seeds = try decodedSeeds([
            violation(effect: PBTSeedEffect(
                declared: .idempotent, resolved: .nonIdempotent,
                provenance: .inferredUpward, depth: 3
            ))
        ])
        let effect = try #require(seeds.first?.effect)
        #expect(effect.provenance == .inferredUpward)
        #expect(effect.depth == 3)
    }

    /// A name-based inference is the one a reader most often needs to overrule,
    /// and overruling it requires knowing which name fired.
    @Test("a heuristic inference carries the phrase that matched")
    func downwardCarriesReason() throws {
        let seeds = try decodedSeeds([
            violation(effect: PBTSeedEffect(
                declared: .idempotent, resolved: .nonIdempotent,
                provenance: .inferredDownward, reason: "from the callee name `save`"
            ))
        ])
        let effect = try #require(seeds.first?.effect)
        #expect(effect.provenance == .inferredDownward)
        #expect(effect.reason == "from the callee name `save`")
        #expect(effect.depth == nil)
    }

    // MARK: - The wire vocabulary

    /// The raw values are the annotation-grammar tokens, not Swift case names.
    /// That grammar is the interoperability surface humans, this linter, and
    /// SwiftEffectInference already share; a second spelling in the manifest
    /// would be a fourth dialect of a vocabulary that has one too many.
    @Test("tiers are spelled as the annotation grammar spells them")
    func tiersUseGrammarSpelling() throws {
        let json = PBTSeedsFormatter().format(issues: [
            violation(effect: PBTSeedEffect(
                declared: .externallyIdempotent, resolved: .nonIdempotent, provenance: .declared
            ))
        ])
        #expect(json.contains("\"externally_idempotent\""))
        #expect(json.contains("\"non_idempotent\""))
        #expect(!json.contains("externallyIdempotent"))
        #expect(!json.contains("nonIdempotent"))
    }

    @Test("provenance is spelled in the manifest's kebab-case style")
    func provenanceUsesKebabCase() throws {
        let json = PBTSeedsFormatter().format(issues: [
            violation(effect: PBTSeedEffect(
                declared: .idempotent, resolved: .nonIdempotent,
                provenance: .inferredUpward, depth: 1
            ))
        ])
        #expect(json.contains("\"inferred-upward\""))
    }

    // MARK: - Absence

    /// Every other seed must stay byte-identical to one written before this
    /// field existed, or an additive change becomes a breaking one for any
    /// consumer diffing manifests.
    @Test("a seed without an effect omits the key entirely")
    func absentEffectIsOmitted() throws {
        let pureCandidate = LintIssue(
            severity: .info,
            message: "`add(…)` looks pure and total",
            filePath: "Math.swift",
            lineNumber: 3,
            suggestion: "Run swift-infer discover",
            ruleName: .pureFunctionCandidate,
            symbol: "add"
        )
        let json = PBTSeedsFormatter().format(issues: [pureCandidate])
        #expect(!json.contains("\"effect\""))
        let seeds = try decodedSeeds([pureCandidate])
        #expect(seeds.first?.effect == nil)
    }

    /// `depth` and `reason` decode leniently; the three that would have to be
    /// guessed do not. Guessing a tier or a provenance invents a claim the
    /// linter never made.
    @Test("an effect without depth or reason decodes")
    func minimalEffectDecodes() throws {
        let json = """
        {"version":2,"seeds":[{"file":"A.swift","line":1,"symbol":"f","rule":"Idempotency Violation",
        "kind":"idempotency","effect":{"declared":"idempotent","resolved":"non_idempotent",
        "provenance":"declared"}}]}
        """
        let data = try #require(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(PBTSeedManifest.self, from: data)
        let effect = try #require(manifest.seeds.first?.effect)
        #expect(effect.depth == nil)
        #expect(effect.reason == nil)
    }

    @Test("an effect missing its provenance is rejected rather than guessed")
    func missingProvenanceIsRejected() throws {
        let json = """
        {"version":2,"seeds":[{"file":"A.swift","line":1,"symbol":"f","rule":"Idempotency Violation",
        "kind":"idempotency","effect":{"declared":"idempotent","resolved":"non_idempotent"}}]}
        """
        let data = try #require(json.data(using: .utf8))
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(PBTSeedManifest.self, from: data)
        }
    }
}

/// `anchor` — what an `inferred-upward` chain bottoms out on.
///
/// `provenance` names the **final hop**: how the immediate callee's effect was
/// known, and nothing about the chain beneath it. Because
/// `IdempotencyViolationVisitor` supplies `HeuristicEffectInferrer` as the anchor
/// resolver to `applyBodyInference`, an upward chain can bottom out on a name
/// guess. A consumer reading provenance alone therefore had to withhold *every*
/// upward tier — SwiftInferProperties did exactly that, keeping only the
/// direct-callee case it could verify itself, and the multi-hop reach this
/// linter uniquely has went unused.
///
/// This field separates the two. A `declaration`-anchored multi-hop chain is
/// precisely the signal a consumer cannot compute for itself: its own pass runs
/// one hop against a 2-second budget.
@Suite("PBT seeds — what an upward chain rests on")
struct PBTSeedAnchorTests {

    private func seed(_ effect: PBTSeedEffect) -> LintIssue {
        LintIssue(
            severity: .error,
            message: "`confirmOrder` claims idempotence but calls non-idempotent work",
            filePath: "Orders.swift",
            lineNumber: 11,
            suggestion: "Route it through an idempotency key",
            ruleName: .idempotencyViolation,
            symbol: "confirmOrder",
            effect: effect
        )
    }

    private func decoded(_ effect: PBTSeedEffect) throws -> PBTSeed {
        let json = PBTSeedsFormatter().format(issues: [seed(effect)])
        let data = try #require(json.data(using: .utf8))
        let manifest = try JSONDecoder().decode(PBTSeedManifest.self, from: data)
        return try #require(manifest.seeds.first)
    }

    @Test("a declaration-anchored chain says so")
    func declarationAnchorSurvives() throws {
        let seed = try decoded(PBTSeedEffect(
            declared: .idempotent, resolved: .nonIdempotent,
            provenance: .inferredUpward, depth: 3, anchor: .declaration
        ))
        #expect(seed.effect?.anchor == .declaration)
        #expect(seed.effect?.depth == 3)
    }

    @Test("a guess-anchored chain says so")
    func heuristicAnchorSurvives() throws {
        let seed = try decoded(PBTSeedEffect(
            declared: .idempotent, resolved: .nonIdempotent,
            provenance: .inferredUpward, depth: 3, anchor: .heuristic
        ))
        #expect(seed.effect?.anchor == .heuristic)
    }

    /// **Depth and anchor are independent, and this is the pair that shows why.**
    /// Same tier, same distance, different trustworthiness — before this field a
    /// consumer saw these two as identical documents.
    @Test("depth alone cannot distinguish the two")
    func depthDoesNotImplyAnchor() throws {
        let clean = try decoded(PBTSeedEffect(
            declared: .idempotent, resolved: .nonIdempotent,
            provenance: .inferredUpward, depth: 4, anchor: .declaration
        ))
        let tainted = try decoded(PBTSeedEffect(
            declared: .idempotent, resolved: .nonIdempotent,
            provenance: .inferredUpward, depth: 4, anchor: .heuristic
        ))
        #expect(clean.effect?.depth == tainted.effect?.depth)
        #expect(clean.effect?.anchor != tainted.effect?.anchor)
    }

    /// A declaration *is* the anchor; a heuristic match is a guess by
    /// construction. Emitting the field for either would be noise a consumer has
    /// to learn to ignore, and every key that must be ignored is one a future
    /// reader may act on by mistake.
    @Test("the other provenances omit the key entirely", arguments: [
        PBTSeedEffect.Provenance.declared, .inferredDownward
    ])
    func otherProvenancesOmitAnchor(provenance: PBTSeedEffect.Provenance) throws {
        let json = PBTSeedsFormatter().format(issues: [seed(PBTSeedEffect(
            declared: .idempotent, resolved: .nonIdempotent, provenance: provenance
        ))])
        #expect(!json.contains("anchor"))
    }

    /// The wire spelling is `declaration`, not the producer's internal
    /// `declared` — deliberately distinct from `Provenance.declared`, which is a
    /// different question about a different hop. Two fields whose values read
    /// the same invite exactly the conflation this whole field exists to undo.
    @Test("the anchor spelling is distinct from the provenance spelling")
    func anchorSpellingIsDistinct() {
        #expect(PBTSeedEffect.Anchor.declaration.rawValue == "declaration")
        #expect(PBTSeedEffect.Provenance.declared.rawValue == "declared")
    }
}

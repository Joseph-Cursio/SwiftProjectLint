import Foundation

/// The effect-lattice position of a seeded symbol, as the linter resolved it.
///
/// ## Why the manifest needs this
///
/// `PBTSeedKind.idempotency` tells a consumer *that* a symbol violated its
/// idempotency claim. It does not say what the claim was, what the body turned
/// out to be, or how confidently the linter knows — and those are the three
/// things a downstream tool needs before it may act.
///
/// SwiftInferProperties records the gap from the other side. Its
/// `IdempotenceTemplate+DeclaredEffect` reads the author's annotation off the
/// declaration and notes that the linter *"computes strictly more from the same
/// vocabulary — an `EffectSymbolTable` resolving cross-file, multi-hop upward
/// inference through the call graph, and a heuristic inferrer for unannotated
/// callees — and none of that crosses into `.pbt/seeds.json`, which carries the
/// idempotency violation but not the tier."* This type is that crossing.
///
/// The valuable half is `resolved`, not `declared`. A consumer parsing the same
/// source can read the declaration itself; what it cannot reproduce is a
/// cross-file, multi-hop resolution of what the body actually reaches. That is
/// knowledge only the linter has, and it dies at the manifest boundary without
/// this field.
///
/// ## Why provenance travels with the tier
///
/// The consumer's treatments are not the same: a declaration **vetoes** a
/// proposed law, an inference **demotes** it. Emitting a bare tier would force
/// the consumer to guess which it was holding, and either guess is a real cost —
/// treating an inference as a declaration suppresses laws that might be true,
/// and treating a declaration as an inference dilutes the strongest signal the
/// author ever gave. A tier without its provenance is not a weaker version of
/// this field; it is one the consumer cannot safely use.
public struct PBTSeedEffect: Codable, Sendable, Equatable {

    /// One position on the effect lattice, spelled as the annotation grammar
    /// spells it.
    ///
    /// The raw values are the doc-comment tokens (`non_idempotent`, not
    /// `nonIdempotent`) because that grammar is the interoperability surface
    /// this whole pipeline shares — humans write it, the linter enforces it, and
    /// SwiftEffectInference parses it. A second spelling in the manifest would
    /// be a fourth dialect of a vocabulary that already has one too many.
    public enum Tier: String, Codable, Sendable {
        case pure
        case idempotent
        case observational
        case externallyIdempotent = "externally_idempotent"
        case nonIdempotent = "non_idempotent"
    }

    /// How the linter came to know `resolved` — and therefore how much weight a
    /// consumer may put on it.
    public enum Provenance: String, Codable, Sendable {
        /// The author annotated the callee. The strongest signal available, and
        /// the only one that should veto rather than demote.
        case declared

        /// Resolved by walking bodies up the call graph — the lattice join of a
        /// function's callees, iterated to a fixed point across files. Carries a
        /// `depth`; see that field for why it is not decoration, and an
        /// `anchor`, without which a consumer cannot act on it at all.
        case inferredUpward = "inferred-upward"

        /// Matched by the heuristic name/framework inferrer (`save` on a Fluent
        /// `Model`, `upsert`, a logger receiver). Weakest of the three: it is a
        /// claim about a name, not about a body, so `reason` travels with it so
        /// a reader can judge the match rather than take it.
        case inferredDownward = "inferred-downward"
    }

    /// What the seeded symbol *claims* — the effect annotated on its own
    /// declaration.
    ///
    /// Always present for an `idempotency` seed: the rule only analyses
    /// functions carrying an effect annotation, so a violation cannot exist
    /// without one.
    public let declared: Tier

    /// What the linter found the body actually reaches, and the reason the claim
    /// was judged violated.
    public let resolved: Tier

    /// How `resolved` was arrived at.
    public let provenance: Provenance

    /// Hops back to a declared or heuristic anchor, counting this function as
    /// one. `nil` unless `provenance == .inferredUpward`.
    ///
    /// Confidence, not trivia. `depth: 1` means every contributing callee was
    /// itself annotated — nearly as good as a declaration. `depth: 4` means the
    /// tier survived three intermediate functions nobody annotated, and each hop
    /// is somewhere the inference could have taken a wrong branch. A consumer
    /// that wants to weight by confidence has no other way to.
    public let depth: Int?

    /// For an upward inference, whether the chain bottomed out on annotations
    /// or on a guess. `nil` for the other two provenances, where the question
    /// does not arise — a declaration *is* the anchor, and a heuristic match is
    /// a guess by construction.
    ///
    /// **This is what makes `inferred-upward` usable rather than merely
    /// reported.** `provenance` names the final hop; it says how the immediate
    /// callee's effect was known and nothing about the chain beneath it. Because
    /// `IdempotencyViolationVisitor` supplies `HeuristicEffectInferrer` as the
    /// anchor resolver to `applyBodyInference`, an upward chain can bottom out
    /// on a name guess — so a consumer reading provenance alone had to withhold
    /// every upward tier, which SwiftInferProperties did, keeping only the
    /// direct-callee case. This field separates the two, and a
    /// `declaration`-anchored multi-hop chain is precisely the signal a consumer
    /// cannot compute for itself: its own pass runs one hop against a 2-second
    /// budget.
    public let anchor: Anchor?

    /// What an upward chain rests on. Mirrors
    /// `SwiftEffectInference.BodyInference.Anchor`, translated rather than
    /// shared for the same reason `Tier` is: the manifest is a versioned wire
    /// format and must not move because a dependency renamed a case.
    public enum Anchor: String, Codable, Sendable {
        /// Every step justifying the tier was a human annotation.
        case declaration
        /// At least one step was a name or framework guess.
        case heuristic
    }

    /// For a heuristic match, the phrase naming what matched — *"from the callee
    /// name `save`"*, *"from the known-idempotent Fluent type `QueryBuilder`"*.
    ///
    /// Carried because a name-based inference is the one a reader most often
    /// needs to overrule, and overruling it requires knowing which name fired.
    /// `nil` for the other two provenances, where the answer is "the author said
    /// so" or "the call graph said so".
    public let reason: String?

    public init(
        declared: Tier,
        resolved: Tier,
        provenance: Provenance,
        depth: Int? = nil,
        anchor: Anchor? = nil,
        reason: String? = nil
    ) {
        self.declared = declared
        self.resolved = resolved
        self.provenance = provenance
        self.depth = depth
        self.anchor = anchor
        self.reason = reason
    }

    /// `depth` and `reason` decode leniently; the other three are required.
    ///
    /// The asymmetry is the same one `PBTSeed` applies to `kind` versus `role`:
    /// a field whose absence has an honest reading ("no hop count, because this
    /// was not an upward inference") may be optional, and a field whose absence
    /// would have to be guessed may not. Guessing a tier or a provenance would
    /// invent a claim the linter never made.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.declared = try container.decode(Tier.self, forKey: .declared)
        self.resolved = try container.decode(Tier.self, forKey: .resolved)
        self.provenance = try container.decode(Provenance.self, forKey: .provenance)
        self.depth = try container.decodeIfPresent(Int.self, forKey: .depth)
        self.anchor = try container.decodeIfPresent(Anchor.self, forKey: .anchor)
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }
}

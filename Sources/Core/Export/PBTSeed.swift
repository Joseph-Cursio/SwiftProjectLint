import Foundation
import SwiftProjectLintModels

/// A single property-based-test seed: a place the linter judged worth a property test, identified
/// precisely enough for a downstream tool (`swift-infer`) to act on it.
///
/// `kind` decides *how* to act — see `PBTSeedKind`. A consumer that ignores `kind` and treats every
/// seed as an analysable symbol will narrow itself to zero on the kernels.
public struct PBTSeed: Codable, Sendable {
    public let file: String
    public let line: Int
    public let symbol: String
    public let rule: String
    public let kind: PBTSeedKind

    /// What the logic **is** — comparator, predicate, partition — when the rule classified it.
    ///
    /// `symbol` says where to look; `kind` says whether a tool can call it yet; this says what law
    /// it owes. Absent when the rule that produced the seed classifies nothing.
    ///
    /// **Three rules classify**, and naming them is the point — the count has already drifted once:
    ///
    /// - `.pureFunctionCandidate` — `PureFunctionCandidateVisitor`, via `DeclaredRoleClassifier`
    /// - `.pureClosureCandidate` — `PureClosureCandidateVisitor`, via `seedRole`
    /// - `.extractableTotalKernel` — `ExtractableTotalKernelVisitor`, via `kernel.role`
    ///
    /// This said *"every rule but the two candidate rules"* until 2026-08-04, which was wrong twice
    /// over: the count was stale, and the description ruled the third one out **by name** —
    /// `extractableTotalKernel` is a kernel rule, not a candidate rule, so a reader checking the
    /// sentence against the code would have concluded the classification it saw there was a bug.
    /// A doc that characterises a set by a property its newest member lacks does not merely go out
    /// of date; it argues against the code.
    ///
    /// Encoded only when present, so a seed with no role is byte-identical to one written before
    /// this field existed.
    public let role: PBTSeedRole?

    /// For a `restricted-function`, **what a consumer would have to widen** — see `TestRestriction`.
    ///
    /// `kind` says a test cannot reach this symbol; this says whether the remedy is one keyword on
    /// the declaration or a change to an enclosing type. The two are not interchangeable: widening a
    /// member nested inside a `private` type compiles and changes nothing, so a consumer acting on
    /// the kind alone can emit a patch that unblocks nothing and then blame the property when
    /// verification fails.
    ///
    /// `nil` for every other kind, and encoded only when present — a seed without it is
    /// byte-identical to one written before this field existed.
    public let restriction: TestRestriction?

    /// Where the seeded symbol sits on the effect lattice — what it claimed,
    /// what its body reached, and how the linter knows.
    ///
    /// Only `idempotency` seeds carry one; the other kinds are about purity and
    /// callability, which the lattice does not speak to. Encoded only when
    /// present, so every other seed stays byte-identical to one written before
    /// this field existed.
    ///
    /// This is the field that closes the gap SwiftInferProperties named from the
    /// other side: the linter resolves effects cross-file and multi-hop, the
    /// consumer can only read the declaration in front of it, and until now none
    /// of the difference crossed the manifest boundary.
    public let effect: PBTSeedEffect?

    /// The conformances the symbol is still waiting on — see `PBTSeedRequirement`.
    ///
    /// Only `missingEquatableOnPureResult` sets it: a pure function refused as a candidate solely
    /// because its result is not `Equatable`, when a bare conformance would synthesize. A consumer
    /// that ignores it sees an ordinary `pure-function` whose result has no `==` — the case
    /// `swift-infer` already caveats — so absence loses the remedy and misreads nothing. Encoded only
    /// when present, so every other seed stays byte-identical to one written before this field
    /// existed.
    public let requires: PBTSeedRequirement?

    /// What a `pure-mutator` writes: `"self"`, or the internal name of its one `inout` parameter —
    /// the argument a consumer passes with `&`. Only that kind carries it, and it is encoded only
    /// when present, so every other seed stays byte-identical.
    public let mutates: String?

    public init(
        file: String,
        line: Int,
        symbol: String,
        rule: String,
        kind: PBTSeedKind,
        role: PBTSeedRole? = nil,
        restriction: TestRestriction? = nil,
        effect: PBTSeedEffect? = nil,
        requires: PBTSeedRequirement? = nil,
        mutates: String? = nil
    ) {
        self.file = file
        self.line = line
        self.symbol = symbol
        self.rule = rule
        self.kind = kind
        self.role = role
        self.restriction = restriction
        self.effect = effect
        self.requires = requires
        self.mutates = mutates
    }

    /// `kind` is **required**, mirroring the consumer.
    ///
    /// It used to default to `.pureFunction` so a v1 manifest still decoded. No v1 manifest can
    /// exist any more — `currentVersion` is a constant 2 and manifests are generated on demand
    /// rather than archived, so nothing was ever written that lacks the field. Worse, the default
    /// was SILENT on the one field whose misreading the v1 -> v2 bump existed to prevent: a seed
    /// read as `.pureFunction` is a seed a consumer may narrow discovery onto, and doing that to an
    /// uncallable kernel produces a confident zero.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.file = try container.decode(String.self, forKey: .file)
        self.line = try container.decode(Int.self, forKey: .line)
        self.symbol = try container.decode(String.self, forKey: .symbol)
        self.rule = try container.decode(String.self, forKey: .rule)
        self.kind = try container.decode(PBTSeedKind.self, forKey: .kind)
        // A manifest from a producer that does not classify roles simply has none — unknown is a
        // legitimate answer. `kind` above is required for the opposite reason: absence there would
        // have to be guessed, and the guess decides whether a consumer may analyse the seed.
        self.role = try container.decodeIfPresent(PBTSeedRole.self, forKey: .role)
        // Same reasoning as `role`: absent is honestly unknown, and only a `restricted-function`
        // ever carries one. A consumer that ignores it loses the remedy, not the finding.
        self.restriction = try container.decodeIfPresent(TestRestriction.self, forKey: .restriction)
        // Same reasoning again: only the idempotency family resolves a lattice
        // position, so absence is an honest "this kind of seed has none" rather
        // than a value to guess at.
        self.effect = try container.decodeIfPresent(PBTSeedEffect.self, forKey: .effect)
        // Same reasoning as `role`: only a near-miss carries one, and absent is "nothing required".
        self.requires = try container.decodeIfPresent(PBTSeedRequirement.self, forKey: .requires)
        // Only a `pure-mutator` carries one; absent is "returns its result".
        self.mutates = try container.decodeIfPresent(String.self, forKey: .mutates)
    }
}

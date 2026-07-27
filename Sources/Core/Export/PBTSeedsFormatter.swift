import Foundation
import SwiftProjectLintModels

/// What a seed *is*, which decides what a consumer may do with it.
///
/// The distinction is the whole reason this field exists, and getting it wrong recreates a bug the
/// pipeline has already had once. A seed is not always "a symbol to analyse":
///
/// - An **analysable** seed names a function `swift-infer` can index, focus on, and propose laws for.
/// - A **refactor-pending** seed names a place where pure logic *exists* but has **no name yet** —
///   an extractable kernel. There is nothing to index. `swift-infer` cannot analyse it, cannot call
///   it, and cannot generate inputs for it, because the thing does not exist as a callable entity
///   until a human draws a boundary around it and names it.
///
/// **Feed a refactor-pending seed to a focus filter and you get a confident zero**: the tool narrows
/// to a symbol it must then refuse (`uploadRemainingChunks` is `private async throws`, which refutes
/// purity), and reports `kept 0` for a codebase that has property-testable logic in it. That is
/// exactly the failure this whole pipeline was rebuilt to eliminate, arriving by a new route. Hence
/// the field, and hence `isAnalysable`.
public enum PBTSeedKind: String, Codable, Sendable {
    /// A pure, total function. Index it, propose laws for it, run them.
    case pureFunction = "pure-function"

    /// A function claiming idempotence that calls non-idempotent work — it arrives with a ready-made
    /// property to verify.
    case idempotency = "idempotency"

    /// Pure logic inlined inside an impure method — real, valuable, and **not yet callable**. The
    /// symbol names the *enclosing* function, which is where to look, not what to test.
    case extractableKernel = "extractable-kernel"

    /// A pure, total, **named** function that no test can call: `private` or `fileprivate`.
    ///
    /// `@testable import` reaches `internal` and no further. This codebase has always known that —
    /// `PropertyTestCandidacy`'s own doc comment says it, and `couldBePrivateMember` exists because
    /// of it — and the seeding path did not apply it. Measured here: **316 of 468 seeds marked
    /// analysable named a function no test could reach**, two thirds of the manifest's supposedly
    /// actionable half.
    ///
    /// The consumer was right and the linter was wrong, which is how this was found: `swift-infer`
    /// declines these under its own `RestrictedFunction` concept, so the two tools disagreed and
    /// the disagreement only became visible once both sides stated their beliefs in a comparable
    /// vocabulary.
    ///
    /// **Analysable, and a label rather than a gate.** This case first shipped with
    /// `isAnalysable == false`, grouping it with `extractableKernel`, and that conflated two
    /// different obstacles:
    ///
    /// | | symbol to analyse? | law proposable? | blocker |
    /// |---|---|---|---|
    /// | `extractableKernel` | no — the logic has no name | no | someone must draw a boundary |
    /// | `restrictedFunction` | **yes** — name and signature | **yes** | one keyword, to *verify* it |
    ///
    /// `isAnalysable` asks whether a consumer may narrow analysis to this symbol. For a private
    /// function the answer is yes; what it cannot do is *verify* the law from another module
    /// without a refactor. Answering the verification question with the analysis flag suppressed
    /// **319 seeds on this repository** — and `swift-infer` has a deliberate feature for exactly
    /// these, keyed on the analysable set, so marking them unanalysable switched it off silently.
    ///
    /// A private helper is often the *best* property target. An app has no public API; its pure
    /// logic lives in `private` helpers. The kind stays because the consumer wants to know — it
    /// leads with the access caveat and names the one refactor that unlocks verification — but
    /// knowing is not the same as refusing.
    case restrictedFunction = "restricted-function"

    /// Whether a consumer may point analysis at this seed's symbol.
    ///
    /// `false` means: report it to the reader as work to do, and **do not** narrow discovery to it.
    /// The symbol is a location, not a subject.
    public var isAnalysable: Bool {
        switch self {
        case .pureFunction, .idempotency, .restrictedFunction:
            return true

        case .extractableKernel:
            return false
        }
    }
}

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
    /// it owes. Absent when the rule that produced the seed classifies nothing, which is every rule
    /// but the two candidate rules.
    ///
    /// Encoded only when present, so a seed with no role is byte-identical to one written before
    /// this field existed.
    public let role: PBTSeedRole?

    public init(
        file: String,
        line: Int,
        symbol: String,
        rule: String,
        kind: PBTSeedKind,
        role: PBTSeedRole? = nil
    ) {
        self.file = file
        self.line = line
        self.symbol = symbol
        self.rule = rule
        self.kind = kind
        self.role = role
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
    }
}

/// The top-level manifest written by the `pbt-seeds` format. `version` lets the consumer evolve the
/// schema without silently misreading an older file.
public struct PBTSeedManifest: Codable, Sendable {
    public let version: Int
    public let seeds: [PBTSeed]

    public init(seeds: [PBTSeed], version: Int = Self.currentVersion) {
        self.version = version
        self.seeds = seeds
    }

    /// The schema version emitted by this build.
    ///
    /// **v2 adds `kind`.** The change is additive and backwards-compatible on read — a v1 manifest
    /// decodes with every seed defaulted to `.pureFunction`, which is what a v1 seed always was — but
    /// a v1 *consumer* reading a v2 manifest will silently ignore `kind` and treat an
    /// `extractable-kernel` as an analysable symbol. That produces a confident zero, so the version
    /// bump is what lets such a consumer notice and say so.
    public static let currentVersion = 2

    /// The seeds a consumer may narrow analysis to. The rest are work for a human first.
    public var analysableSeeds: [PBTSeed] {
        seeds.filter(\.kind.isAnalysable)
    }
}

/// Emits the seeds that drive the `lint → infer → verify` pipeline (Idea #2).
///
/// Projects each seed-worthy finding to a `{file, line, symbol, rule, kind}` record. The result is a
/// `PBTSeedManifest` JSON document, intended to be redirected to `.pbt/seeds.json` and consumed by
/// `swift-infer discover --seeds`. Findings from other rules (and any candidate lacking a resolved
/// symbol) are dropped, so the output is exactly the set of places worth property-testing.
public struct PBTSeedsFormatter: IssueFormatterProtocol {

    /// Rules whose findings name a place worth property-testing, and what kind of place each names.
    ///
    /// Every rule here must populate `LintIssue.symbol`. For an analysable kind the symbol is the
    /// *subject*; for `extractableKernel` it is the enclosing declaration — a **location**, because
    /// the kernel itself has no name yet. That is the point of the rule.
    ///
    /// **`pureClosureCandidate` is a kernel, and leaving it out cost the pipeline its best finding.**
    /// It was held back once as "a separate, deliberate step"; this is that step. A pure closure is
    /// the same refactor-pending shape as an inlined kernel — pure logic with no name, which no tool
    /// can index, call or generate inputs for until a human draws a boundary around it — and it
    /// belongs here on exactly the same terms.
    ///
    /// What it cost: `ExtractablePureKernelVisitor` is arithmetic-shaped, so on the road-test fixture
    /// it seeds `uploadRemainingChunks` and `collect` and **cannot** see `fetchLocalFiles`, whose
    /// logic is a predicate and a comparator rather than a computation. The closure rule *did* fire
    /// on both halves of it and said the right thing — and then the finding died in the formatter,
    /// because a manifest is the only channel the downstream tool reads. So no reader was ever asked
    /// to extract that logic, no comparator law was ever proposed for it, and the bug living in the
    /// predicate was reached by 1 cold reader in 3 — by ignoring the manifest and reading the code.
    ///
    /// The lesson generalises past this rule: **a finding the linter prints but does not seed is a
    /// finding the pipeline does not have.**
    static let seedKinds: [RuleIdentifier: PBTSeedKind] = [
        .pureFunctionCandidate: .pureFunction,
        .idempotencyViolation: .idempotency,
        .extractablePureKernel: .extractableKernel,
        .pureClosureCandidate: .extractableKernel
    ]

    /// Demote an otherwise-analysable seed whose symbol no test can call.
    ///
    /// The rule-to-kind table is static, but reachability is a property of the *declaration*, so the
    /// two have to meet here. Only an analysable kind can be demoted: a kernel is already
    /// refactor-pending, and its reachability is not the obstacle.
    static func effectiveKind(
        _ declared: PBTSeedKind, reachability: TestReachability
    ) -> PBTSeedKind {
        guard declared.isAnalysable, reachability == .unreachable else { return declared }
        return .restrictedFunction
    }

    /// Seed-bearing findings the manifest could not carry, and why.
    ///
    /// A seed with no resolved symbol is dropped — the manifest names *places*, and a place
    /// without a name is not one. That is the right behaviour and the wrong silence: the output is
    /// still valid JSON, still exits 0, and is simply shorter than the run that produced it. A
    /// consumer cannot tell a project with fewer candidates from a project whose candidates fell
    /// out on the way.
    ///
    /// This is not hypothetical. `LintConfiguration.applyOverrides` rebuilt `LintIssue` without
    /// carrying `symbol` across, so configuring a severity on any seed-bearing rule silently
    /// emptied that rule's contribution — a confident zero at the entry point of the whole adoption
    /// loop. The linter's own `lossyStructRebuild` rule reported the responsible line in its
    /// default output and the finding went unread, which is the argument for detecting the loss
    /// *here*, where it happens, rather than hoping someone correlates a lint finding with a short
    /// manifest.
    public struct DroppedSeedReport: Sendable, Equatable {
        /// How many findings each seed-bearing rule lost.
        public let countsByRule: [RuleIdentifier: Int]

        public var total: Int { countsByRule.values.reduce(0, +) }

        public init(countsByRule: [RuleIdentifier: Int]) {
            self.countsByRule = countsByRule
        }

        /// The stderr notice, phrased so the number is the first thing read.
        public var notice: String {
            let lines = countsByRule
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { "  \($0.value) × \($0.key.rawValue)" }
            return """
            Note: \(total) seed-bearing finding\(total == 1 ? "" : "s") had no resolved symbol and \
            were left out of the manifest. The seeds file is correspondingly shorter than this run \
            — it is not a smaller project, it is a lossy hand-off. Each rule below is expected to \
            populate `LintIssue.symbol`; one that does not has usually had the field dropped in a \
            field-by-field rebuild.
            \(lines.joined(separator: "\n"))
            """
        }
    }

    /// The findings a `format(issues:)` call will silently discard, or `nil` when it discards
    /// nothing.
    ///
    /// Deliberately a separate query rather than state on the formatter: `format` stays a pure
    /// function of its input, and the caller decides whether anyone is listening.
    public static func droppedSeeds(in issues: [LintIssue]) -> DroppedSeedReport? {
        var counts: [RuleIdentifier: Int] = [:]
        for issue in issues where seedKinds[issue.ruleName] != nil {
            if issue.symbol?.isEmpty ?? true {
                counts[issue.ruleName, default: 0] += 1
            }
        }
        return counts.isEmpty ? nil : DroppedSeedReport(countsByRule: counts)
    }

    public init() { /* no-op */ }

    public func format(issues: [LintIssue]) -> String {
        let seeds: [PBTSeed] = issues.compactMap { issue in
            guard let declaredKind = Self.seedKinds[issue.ruleName],
                  let symbol = issue.symbol,
                  symbol.isEmpty == false
            else { return nil }
            let kind = Self.effectiveKind(declaredKind, reachability: issue.testReachability)
            return PBTSeed(
                file: issue.filePath,
                line: issue.lineNumber,
                symbol: symbol,
                rule: issue.ruleName.rawValue,
                kind: kind,
                role: issue.role
            )
        }

        let manifest = PBTSeedManifest(seeds: seeds)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(manifest),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{\"seeds\":[],\"version\":\(PBTSeedManifest.currentVersion)}"
        }

        return jsonString
    }
}

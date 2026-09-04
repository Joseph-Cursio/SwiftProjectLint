@testable import Core
import PropertyBased
import SwiftProjectLintModels
import Testing

/// Laws over the reporting order — **the rendered report is a function of the finding *set*, not
/// of the order analysis happened to produce them in.**
///
/// `LintIssue+Ordering` exists to make `diff old.txt new.txt` meaningful between two runs. Per-file
/// analysis collects `TaskGroup` results as they complete, so the incoming order is different every
/// run; `sortedForReporting()` is applied once, in `ProjectLinter`, and every formatter inherits it.
///
/// The guarantee that buys is stated in `LintIssue.precedes`' own doc comment:
///
/// > The components after them exist to make the order **total**: `sorted(by:)` is not guaranteed
/// > stable, so any two findings that compare equal may still swap places between runs. Comparing
/// > on everything the text report prints — rule, message, suggestion — means findings that tie are
/// > byte-identical in the output, so their relative order cannot be observed. `symbol` is the last
/// > resort for the machine-readable formats, which carry fields the text report does not.
///
/// That claim was false, and **not only for the machine-readable formats**. The old comparator
/// chained six components — `filePath`, `lineNumber`, `ruleName`, `message`, `suggestion ?? ""`,
/// `symbol ?? ""` — while four further things reach a formatter:
///
/// | field | compared before | rendered by |
/// |---|---|---|
/// | `severity` | no | **text**, JSON, CSV, HTML |
/// | `locations[1...]` | no — only `locations.first`, via `filePath`/`lineNumber` | JSON, CSV |
/// | `suggestion` / `symbol`, `nil` vs `""` | no — collapsed by `?? ""` | JSON (synthesized `Codable` omits a `nil` key and emits `""` for empty) |
/// | `role`, `effect`, `testReachability` | no | `pbt-seeds` |
///
/// The first row is the sharp one. The doc comment above enumerates what the text report prints as
/// "rule, message, suggestion", but `TextFormatter` renders
/// `filepath:line: severity: [rule] message` — **severity is printed on every line and was not
/// compared**. So the drift reached the primary human-facing report, not just the exports, and the
/// comparator's own justification is where it hid.
///
/// So two findings could tie under `precedes`, render differently, and — `sorted(by:)` being
/// unstable — swap places between runs. That is the regression-diff problem the ordering was
/// written to eliminate, and it was open for every format the linter emits.
///
/// ## Why the existing tests did not catch it
///
/// `ProjectLinterOrderingTests.testOrderIsTotalAcrossShuffles` asserts exactly this guarantee and
/// passes. Its three fixtures differ in `message` — a field the comparator *does* compare — so the
/// tie it is looking for never occurs, and it cannot see the fields the comparator ignores.
/// `testRepeatedRunsRenderIdenticalText` renders through `TextFormatter` only, the one format whose
/// fields the comparator covers. Both are green, both are about the right thing, and between them
/// they ratify the gap.
///
/// ## On the deliberately narrow alphabet
///
/// **This law is collision-dependent**: it can only fail where two findings *tie*, which needs a
/// collision on all six compared components at once. A generator drawing realistic findings would
/// essentially never produce one, and would report success by missing it. So the pool below is
/// hand-built to collide — every witness pair is identical on all six compared components and
/// differs in exactly one uncompared field — and the generator quantifies over the **arrival
/// order**, which is the thing that actually varies run to run.
@Suite
struct ReportOrderDeterminismLawsTests {

    // MARK: - The witness pairs

    /// Two findings that tie under `precedes` and differ only in `severity`.
    private static let severityPair = [
        makeIssue(message: "same", severity: .error),
        makeIssue(message: "same", severity: .warning)
    ]

    /// Two findings that tie under `precedes` and differ only in their *second* location.
    /// `filePath`/`lineNumber` read `locations.first`, so the tail is invisible to the comparator
    /// and fully rendered by JSON and CSV.
    private static let locationTailPair = [
        makeIssue(message: "multi", locations: [("A.swift", 1), ("B.swift", 5)]),
        makeIssue(message: "multi", locations: [("A.swift", 1), ("C.swift", 9)])
    ]

    /// Two findings that tie under `precedes` because it collapses `nil` and `""` through `?? ""`,
    /// while synthesized `Codable` distinguishes them: a `nil` key is omitted, an empty one is
    /// emitted as `""`.
    private static let nilVersusEmptyPair = [
        makeIssue(message: "optional", suggestion: nil),
        makeIssue(message: "optional", suggestion: "")
    ]

    /// Two seed-bearing findings that tie under `precedes` and differ only in `role` — the field
    /// the linter exists to hand to `swift-infer`, and the one that says what law the symbol owes.
    private static let seedRolePair = [
        makeIssue(message: "seed", ruleName: .pureFunctionCandidate, symbol: "kernel", role: .comparator),
        makeIssue(message: "seed", ruleName: .pureFunctionCandidate, symbol: "kernel", role: .predicate)
    ]

    /// A function rather than a stored `static let`: `any IssueFormatterProtocol` is not `Sendable`,
    /// and a global holding one is shared mutable state as far as the compiler is concerned.
    private static func witnesses() -> [(name: String, pair: [LintIssue], formatter: any IssueFormatterProtocol)] {
        [
            ("severity", severityPair, JSONFormatter()),
            ("locations tail", locationTailPair, JSONFormatter()),
            ("suggestion nil vs \"\"", nilVersusEmptyPair, JSONFormatter()),
            ("seed role", seedRolePair, PBTSeedsFormatter())
        ]
    }

    // MARK: - L1 — every rendered field is compared

    /// **L1 — the comparator separates each witness pair.** Exactly one of the two precedes the
    /// other.
    ///
    /// Each pair is identical on every *other* component and differs in exactly one field that a
    /// formatter renders, so this is the direct statement that the field is compared. Before the
    /// comparator was completed all four pairs **tied** here, and L2 then caught them rendering
    /// differently; this law is the same finding stated where it is cheapest to read.
    ///
    /// Asserted separately from L2 so a failure says which half broke: this one names the field
    /// that went blind, L2 names the format that observed it.
    @Test
    func everyRenderedFieldIsComparedByPrecedes() {
        for (name, pair, _) in Self.witnesses() {
            let forward = LintIssue.precedes(pair[0], pair[1])
            let backward = LintIssue.precedes(pair[1], pair[0])

            #expect(
                forward != backward,
                """
                The '\(name)' pair ties under LintIssue.precedes. These two findings differ only \
                in that field, and a formatter renders it — so sorted(by:), which is not stable, \
                decides their order and the report can change between runs over unchanged sources.
                """
            )
        }
    }

    // MARK: - L2 — a tie is unobservable

    /// **L2 — findings that tie under `precedes` render identically.**
    ///
    /// This is `precedes`' documented claim, stated as a law. A tie that renders differently is a
    /// pair whose position in the report is decided by `sorted(by:)`'s unspecified behaviour on
    /// equal elements, which is precisely what the ordering exists to remove.
    @Test
    func tiedFindingsAreIndistinguishableInEveryFormat() {
        for (name, pair, formatter) in Self.witnesses() {
            let forward = formatter.format(issues: pair.sortedForReporting())
            let backward = formatter.format(issues: pair.reversed().sortedForReporting())

            #expect(
                forward == backward,
                """
                Two findings tie under LintIssue.precedes but render differently in \
                \(type(of: formatter)) — they differ in '\(name)', which the comparator does not \
                compare. sorted(by:) is not stable, so their order in the report is unspecified \
                and can change between runs over unchanged sources.
                """
            )
        }
    }

    // MARK: - L3 — the report is a function of the finding set

    /// **L3 — permutation invariance.** For any arrival order of the same findings, every formatter
    /// renders the same bytes.
    ///
    /// The general form of L2, and the one that keeps earning its keep: it fails the day a field is
    /// added to a formatter without being added to the comparator, which is how all four witnesses
    /// above came to exist.
    ///
    /// Quantified over arrival order rather than over findings, because arrival order is what
    /// actually varies between runs — the finding set is the same, the `TaskGroup` completion order
    /// is not.
    @Test
    func everyFormatRendersTheSameBytesForAnyArrivalOrder() async {
        let pool = Self.witnesses().flatMap(\.pair)
        let formatters: [any IssueFormatterProtocol] = [
            TextFormatter(), JSONFormatter(), CSVFormatter(), HTMLFormatter(), PBTSeedsFormatter()
        ]
        let reference = formatters.map { $0.format(issues: pool.sortedForReporting()) }

        await propertyCheck(input: Gen<[LintIssue]>.shuffled(pool)) { arrival in
            let sorted = arrival.sortedForReporting()
            for (index, formatter) in formatters.enumerated() {
                #expect(
                    formatter.format(issues: sorted) == reference[index],
                    """
                    \(type(of: formatter)) rendered different bytes for a different arrival order \
                    of the same findings. Two findings tie under LintIssue.precedes and are not \
                    byte-identical in this format, so sorted(by:) decides their positions.
                    """
                )
            }
        }
    }

    // MARK: - Fixtures

    /// Every default is chosen so that two calls differing in one argument tie under `precedes` —
    /// the compared components are fixed unless a witness deliberately varies one.
    private static func makeIssue(
        message: String,
        severity: IssueSeverity = .warning,
        locations: [(filePath: String, lineNumber: Int)] = [("A.swift", 1)],
        suggestion: String? = "fix it",
        ruleName: RuleIdentifier = .forceUnwrap,
        symbol: String? = nil,
        role: PBTSeedRole? = nil
    ) -> LintIssue {
        LintIssue(
            severity: severity,
            message: message,
            locations: locations,
            suggestion: suggestion,
            ruleName: ruleName,
            symbol: symbol,
            role: role
        )
    }
}

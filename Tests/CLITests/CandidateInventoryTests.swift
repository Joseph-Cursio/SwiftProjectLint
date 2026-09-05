@testable import CLI
@testable import Core
import SwiftProjectLintModels
import Testing

/// Collapsing the property-test candidate census out of the default text report.
///
/// The behaviour under test is a presentation change with a hard constraint behind it: the CLI
/// computes `issues` **once** and gives the same array to the report formatter and to
/// `PBTSeedsFormatter`. Anything that removes candidates from that array empties the seed manifest
/// and stops the linter feeding `swift-infer`. So the tests that matter most here are the ones
/// asserting what is *still* complete.
@Suite("Property-test candidate inventory")
struct CandidateInventoryTests {

    private func issue(_ rule: RuleIdentifier, severity: IssueSeverity = .info) -> LintIssue {
        LintIssue(
            severity: severity,
            message: "m",
            filePath: "A.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: rule
        )
    }

    private func corpus() -> [LintIssue] {
        [
            issue(.pureFunctionCandidate),
            issue(.pureFunctionCandidate),
            issue(.pureClosureCandidate),
            issue(.extractableTotalKernel),
            issue(.globalMutableState, severity: .warning),
            issue(.idempotencyViolation, severity: .error)
        ]
    }

    // MARK: - What gets withheld

    @Test("only the two candidate rules are withheld")
    func onlyCandidatesAreWithheld() {
        let split = CandidateInventory.split(corpus(), collapsing: true)
        #expect(split.withheld.count == 3)
        #expect(Set(split.withheld.map(\.ruleName)) == [.pureFunctionCandidate, .pureClosureCandidate])
    }

    @Test("a diagnosing rule in the same category stays listed")
    func kernelRuleStaysListed() {
        // `.extractableTotalKernel` is `.testability` and seeds the pipeline, like the two above.
        // It stays because of what it asks of the reader: a candidate rule NOMINATES ("this is
        // pure"), with nothing to do per item, while the kernel rule DIAGNOSES a specific place and
        // proposes a refactor that can be wrong. Volume is the symptom; that is the criterion.
        let listed = CandidateInventory.split(corpus(), collapsing: true).listed
        #expect(listed.map(\.ruleName).contains(.extractableTotalKernel))
    }

    @Test("an error-severity seeding rule is never withheld")
    func idempotencyViolationStaysListed() {
        // `.idempotencyViolation` also feeds the seed manifest, so deriving the withheld set from
        // `PBTSeedsFormatter.seedKinds` would have swallowed it. It reports a contract that is
        // already broken. Seeding the pipeline and being a census are different properties.
        let listed = CandidateInventory.split(corpus(), collapsing: true).listed
        #expect(listed.contains { $0.ruleName == .idempotencyViolation })
    }

    @Test("nothing is withheld when not collapsing")
    func collapsingOffKeepsEverything() {
        let split = CandidateInventory.split(corpus(), collapsing: false)
        #expect(split.listed.count == corpus().count)
        #expect(split.withheld.isEmpty)
    }

    @Test("no issue is ever lost")
    func splitIsATiling() {
        let split = CandidateInventory.split(corpus(), collapsing: true)
        #expect(split.listed.count + split.withheld.count == corpus().count)
    }

    // MARK: - The summary must not undercount

    @Test("the summary counts withheld candidates, and the notice names them")
    func summaryCountsEverything() {
        let split = CandidateInventory.split(corpus(), collapsing: true)
        let output = TextFormatter(withheld: split.withheld).format(issues: split.listed)

        // The whole reason `withheld` is held by the formatter rather than filtered by the caller.
        // "Found 3 issues" for a run that found 6 is the same species of lie as a confident zero.
        #expect(output.contains("Found 6 issues"))
        #expect(output.contains("3 of these are property-test candidates, not listed above"))
        #expect(output.contains("--categories testability"))
        #expect(output.contains("--format pbt-seeds"))
    }

    @Test("a report with no candidates carries no notice")
    func noNoticeWithoutCandidates() {
        let output = TextFormatter().format(issues: [issue(.globalMutableState, severity: .warning)])
        #expect(output.contains("not listed above") == false)
        #expect(output.contains("Found 1 issue"))
    }

    // MARK: - Which surfaces collapse

    @Test("text collapses by default")
    func textCollapses() {
        let output = SwiftProjectLintCLI.render(corpus(), format: .text, selectedCategories: nil)
        #expect(output.contains("not listed above"))
    }

    @Test("asking for the testability category is the opt-in")
    func requestingTestabilityListsThem() {
        let output = SwiftProjectLintCLI.render(
            corpus(), format: .text, selectedCategories: [.testability]
        )
        #expect(output.contains("not listed above") == false)
        #expect(output.contains("Found 6 issues"))
    }

    @Test("selecting an unrelated category still collapses")
    func unrelatedCategoryStillCollapses() {
        let output = SwiftProjectLintCLI.render(
            corpus(), format: .text, selectedCategories: [.architecture]
        )
        #expect(output.contains("not listed above"))
    }

    // MARK: - Skipped scope reaches every text reading (#95)

    @Test("the collapsed text summary carries the skipped-scope caveat")
    func collapsedTextCarriesCaveat() {
        let output = SwiftProjectLintCLI.render(
            corpus(), format: .text, selectedCategories: nil,
            skippedNestedPackages: ["MyLibCore"]
        )
        #expect(output.contains("excludes nested package MyLibCore"))
    }

    /// The seam this nearly shipped without. `--categories testability` skips the
    /// collapsing, and an earlier shape of the guard sent it through the bare
    /// `format.formatter` — dropping the caveat on precisely the request that asks to see
    /// the candidate inventory in full, which is the reading a missing package distorts
    /// most.
    @Test("asking for testability still carries the caveat")
    func testabilityListingCarriesCaveat() {
        let output = SwiftProjectLintCLI.render(
            corpus(), format: .text, selectedCategories: [.testability],
            skippedNestedPackages: ["MyLibCore"]
        )
        #expect(output.contains("not listed above") == false)
        #expect(output.contains("excludes nested package MyLibCore"))
    }

    @Test("machine-readable output is never contaminated with the caveat")
    func machineReadableStaysClean() {
        // The constraint the stderr channel existed to respect in the first place: a JSON
        // consumer parses this. Prose in it is a break, not a courtesy — a machine-readable
        // channel wanting this fact wants it as a field.
        for format in [OutputFormat.json, .csv, .pbtSeeds] {
            let output = SwiftProjectLintCLI.render(
                corpus(), format: format, selectedCategories: nil,
                skippedNestedPackages: ["MyLibCore"]
            )
            #expect(output.contains("excludes nested package") == false)
        }
    }

    /// The constraint this whole design exists to respect: the machine-readable formats must stay
    /// complete, because `pbt-seeds` IS the pipeline and a JSON consumer filters for itself.
    @Test("machine-readable formats are never collapsed", arguments: [OutputFormat.json, .csv, .pbtSeeds])
    func machineFormatsStayComplete(format: OutputFormat) {
        let output = SwiftProjectLintCLI.render(corpus(), format: format, selectedCategories: nil)
        #expect(output.contains("not listed above") == false)
        #expect(output.isEmpty == false)
    }

    @Test("the seed manifest still carries every candidate after a collapsed text run")
    func seedsSurviveCollapsing() {
        // The failure this guards against is subtle and total: collapse in the wrong place and the
        // linter silently stops seeding `swift-infer`, which reports a confident zero for a
        // codebase full of candidates.
        _ = SwiftProjectLintCLI.render(corpus(), format: .text, selectedCategories: nil)
        let json = PBTSeedsFormatter().format(issues: corpus().map {
            LintIssue(
                severity: $0.severity, message: $0.message, filePath: $0.filePath,
                lineNumber: $0.lineNumber, suggestion: nil, ruleName: $0.ruleName, symbol: "f"
            )
        })
        #expect(json.contains("pure-function"))
        #expect(json.contains("extractable-kernel"))
    }

    // MARK: - The tally

    @Test("the tally is ordered by descending count")
    func tallyOrdering() {
        let tally = CandidateInventory.tally(of: [
            issue(.pureClosureCandidate),
            issue(.pureFunctionCandidate),
            issue(.pureFunctionCandidate)
        ])
        #expect(tally.map(\.rule) == [.pureFunctionCandidate, .pureClosureCandidate])
        #expect(tally.map(\.count) == [2, 1])
    }
}

@testable import Core
import Foundation
import Testing

/// The seed manifest reports its own losses.
///
/// `PBTSeedsFormatter` drops a seed-bearing finding that carries no resolved symbol, which is
/// correct — the manifest names *places*, and a place without a name is not one. The silence was
/// the defect: the output stays valid JSON, still exits 0, and is simply shorter than the run
/// behind it, so a consumer cannot distinguish a project with fewer candidates from one whose
/// candidates fell out on the way.
///
/// This is the shape of the bug that motivated it. `LintConfiguration.applyOverrides` rebuilt
/// `LintIssue` field-by-field without carrying `symbol`, so configuring a severity on any
/// seed-bearing rule silently emptied that rule's contribution to `.pbt/seeds.json`. The linter's
/// own `lossyStructRebuild` rule named the responsible line in its default output and the finding
/// went unread — which is why this detects the loss where it happens rather than relying on
/// somebody correlating a lint finding with a short manifest.
@Suite
struct DroppedSeedReportTests {

    private func issue(
        _ rule: RuleIdentifier,
        symbol: String?,
        line: Int = 1
    ) -> LintIssue {
        LintIssue(
            severity: .info,
            message: "candidate",
            filePath: "Widget.swift",
            lineNumber: line,
            suggestion: nil,
            ruleName: rule,
            symbol: symbol
        )
    }

    // MARK: - Reports a loss

    @Test
    func aSeedBearingIssueWithNoSymbolIsReported() throws {
        let report = try #require(
            PBTSeedsFormatter.droppedSeeds(in: [issue(.pureFunctionCandidate, symbol: nil)])
        )
        #expect(report.total == 1)
        #expect(report.countsByRule[.pureFunctionCandidate] == 1)
    }

    /// An empty string is as unusable as `nil` — the formatter rejects both, so both must count.
    @Test
    func anEmptySymbolCountsAsDropped() throws {
        let report = try #require(
            PBTSeedsFormatter.droppedSeeds(in: [issue(.pureFunctionCandidate, symbol: "")])
        )
        #expect(report.total == 1)
    }

    @Test
    func lossesAreCountedPerRule() throws {
        let report = try #require(PBTSeedsFormatter.droppedSeeds(in: [
            issue(.pureFunctionCandidate, symbol: nil, line: 1),
            issue(.pureFunctionCandidate, symbol: nil, line: 2),
            issue(.extractableTotalKernel, symbol: nil, line: 3)
        ]))
        #expect(report.total == 3)
        #expect(report.countsByRule[.pureFunctionCandidate] == 2)
        #expect(report.countsByRule[.extractableTotalKernel] == 1)
    }

    /// The count is the first thing in the notice, and every losing rule is named — a reader who
    /// sees it needs to know which rule to go and fix.
    @Test
    func theNoticeLeadsWithTheCountAndNamesEachRule() throws {
        let report = try #require(PBTSeedsFormatter.droppedSeeds(in: [
            issue(.pureFunctionCandidate, symbol: nil),
            issue(.idempotencyViolation, symbol: nil)
        ]))
        let notice = report.notice
        #expect(notice.hasPrefix("Note: 2 seed-bearing findings"))
        #expect(notice.contains(RuleIdentifier.pureFunctionCandidate.rawValue))
        #expect(notice.contains(RuleIdentifier.idempotencyViolation.rawValue))
        // The point a reader must not miss: short output is not a small project.
        #expect(notice.contains("lossy hand-off"))
    }

    @Test
    func theNoticeIsSingularForOneLoss() throws {
        let report = try #require(
            PBTSeedsFormatter.droppedSeeds(in: [issue(.pureFunctionCandidate, symbol: nil)])
        )
        #expect(report.notice.hasPrefix("Note: 1 seed-bearing finding had"))
    }

    // MARK: - Stays quiet

    @Test
    func nothingIsReportedWhenEverySeedResolves() {
        let issues = [
            issue(.pureFunctionCandidate, symbol: "resolveRules"),
            issue(.extractableTotalKernel, symbol: "applyOverrides")
        ]
        #expect(PBTSeedsFormatter.droppedSeeds(in: issues) == nil)
    }

    /// A rule that is not seed-bearing has no symbol to lose — counting it would report a loss
    /// that never happened, which is the noise this notice must not become.
    @Test
    func nonSeedBearingRulesAreNotCounted() {
        #expect(PBTSeedsFormatter.droppedSeeds(in: [issue(.forceTry, symbol: nil)]) == nil)
    }

    @Test
    func anEmptyRunReportsNothing() {
        #expect(PBTSeedsFormatter.droppedSeeds(in: []) == nil)
    }

    // MARK: - Agreement with the formatter

    /// The report must count exactly what `format` discards. Two independent readings of the same
    /// rule would drift, and a notice that disagrees with the file beside it is worse than none.
    @Test
    func theReportMatchesWhatTheFormatterActuallyDrops() {
        let issues = [
            issue(.pureFunctionCandidate, symbol: "kept", line: 1),
            issue(.pureFunctionCandidate, symbol: nil, line: 2),
            issue(.extractableTotalKernel, symbol: "", line: 3),
            issue(.forceTry, symbol: nil, line: 4)
        ]
        let json = PBTSeedsFormatter().format(issues: issues)
        let emitted = json.components(separatedBy: "\"symbol\"").count - 1
        let dropped = PBTSeedsFormatter.droppedSeeds(in: issues)?.total ?? 0

        #expect(emitted == 1, "only the resolved seed should reach the manifest")
        #expect(dropped == 2, "both seed-bearing losses should be reported")
        // The non-seed-bearing rule is in neither number.
        #expect(emitted + dropped == 3)
    }
}

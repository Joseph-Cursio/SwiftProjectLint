@testable import Core
import Foundation
import Testing

/// Findings come back in a fixed order, so two runs over unchanged sources can be diffed.
///
/// Per-file analysis collects `TaskGroup` results as they complete, which is a different order on
/// every run. That left the report's *contents* stable while ~83% of its lines moved position, so
/// `diff` between two runs reported hundreds of differences that no edit had caused — and the only
/// way to compare two reports was to sort them first, which nothing told the reader to do.
struct ProjectLinterOrderingTests {

    @Test func testIssuesComeBackInReportingOrder() async {
        let projectPath = makeMultiFileProject(named: "OrderingProject")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await ProjectLinter().analyzeProject(
            at: projectPath, detector: system.detector
        )

        #expect(issues.count > 1, "fixture must produce enough findings for order to be observable")
        #expect(firstOutOfOrderPair(in: issues) == nil)
    }

    /// The end-to-end guarantee the report actually rests on: same input, same bytes out.
    ///
    /// Asserted on rendered text rather than on the issue array because the byte-for-byte report is
    /// what a reader diffs, and it is the artifact the ordering exists to protect.
    @Test func testRepeatedRunsRenderIdenticalText() async {
        let projectPath = makeMultiFileProject(named: "OrderingRepeatProject")
        defer { try? FileManager.default.removeItem(atPath: projectPath) }

        let linter = ProjectLinter()
        let formatter = TextFormatter()
        let system = PatternRegistryFactory.createConfiguredSystem()

        var renders: [String] = []
        for _ in 0..<3 {
            let issues = await linter.analyzeProject(at: projectPath, detector: system.detector)
            renders.append(formatter.format(issues: issues))
        }

        #expect(renders.first?.isEmpty == false, "fixture must produce a report to compare")
        #expect(firstDifferingLine(renders[0], renders[1]) == nil)
        #expect(firstDifferingLine(renders[1], renders[2]) == nil)
    }

    /// Sorting is by path, then line, then rule — so one file's findings arrive together and in
    /// source order, which is how a reader scans them.
    @Test func testSortedForReportingOrdersByPathThenLineThenRule() {
        let unsorted = [
            makeIssue(filePath: "B.swift", lineNumber: 1, rule: .forceUnwrap),
            makeIssue(filePath: "A.swift", lineNumber: 9, rule: .forceUnwrap),
            makeIssue(filePath: "A.swift", lineNumber: 2, rule: .missingAccessibilityLabel),
            makeIssue(filePath: "A.swift", lineNumber: 2, rule: .forceUnwrap)
        ]

        let sorted = unsorted.sortedForReporting()

        let keys = sorted.map { "\($0.filePath):\($0.lineNumber):\($0.ruleName.rawValue)" }
        #expect(keys == [
            "A.swift:2:\(RuleIdentifier.forceUnwrap.rawValue)",
            "A.swift:2:\(RuleIdentifier.missingAccessibilityLabel.rawValue)",
            "A.swift:9:\(RuleIdentifier.forceUnwrap.rawValue)",
            "B.swift:1:\(RuleIdentifier.forceUnwrap.rawValue)"
        ])
    }

    /// The order has to be *total*, not merely by path and line: `sorted(by:)` is not guaranteed
    /// stable, so findings that compare equal could still swap places between runs. Sorting a
    /// shuffled array must land in the same place every time.
    @Test func testOrderIsTotalAcrossShuffles() {
        let issues = [
            makeIssue(filePath: "A.swift", lineNumber: 1, rule: .forceUnwrap, message: "first"),
            makeIssue(filePath: "A.swift", lineNumber: 1, rule: .forceUnwrap, message: "second"),
            makeIssue(filePath: "A.swift", lineNumber: 1, rule: .forceUnwrap, message: "third")
        ]

        let expected = issues.sortedForReporting().map(\.message)
        for _ in 0..<20 {
            #expect(issues.shuffled().sortedForReporting().map(\.message) == expected)
        }
    }

    /// The first place the sequence goes backwards, named in one line.
    ///
    /// Returned as a short description rather than asserted with a predicate over the array so a
    /// failure reports the offending pair instead of dumping every `LintIssue` in the fixture.
    private func firstOutOfOrderPair(in issues: [LintIssue]) -> String? {
        for (earlier, later) in zip(issues, issues.dropFirst())
        where LintIssue.precedes(later, earlier) {
            return "\(describe(later)) follows \(describe(earlier))"
        }
        return nil
    }

    private func describe(_ issue: LintIssue) -> String {
        "\(issue.filePath):\(issue.lineNumber) [\(issue.ruleName.rawValue)]"
    }

    /// Where two reports first diverge — the line number plus both sides, rather than two full
    /// reports in the failure output.
    private func firstDifferingLine(_ lhs: String, _ rhs: String) -> String? {
        let lhsLines = lhs.components(separatedBy: "\n")
        let rhsLines = rhs.components(separatedBy: "\n")
        for index in 0..<max(lhsLines.count, rhsLines.count)
        where lhsLines.indices.contains(index) != rhsLines.indices.contains(index)
            || (lhsLines.indices.contains(index) && lhsLines[index] != rhsLines[index]) {
            let lhsLine = lhsLines.indices.contains(index) ? lhsLines[index] : "<missing>"
            let rhsLine = rhsLines.indices.contains(index) ? rhsLines[index] : "<missing>"
            return "line \(index + 1): '\(lhsLine)' vs '\(rhsLine)'"
        }
        return nil
    }

    private func makeIssue(
        filePath: String,
        lineNumber: Int,
        rule: RuleIdentifier,
        message: String = "message"
    ) -> LintIssue {
        LintIssue(
            severity: .warning,
            message: message,
            filePath: filePath,
            lineNumber: lineNumber,
            suggestion: nil,
            ruleName: rule
        )
    }

    /// Enough files, each with several findings, that per-file results genuinely interleave.
    ///
    /// Given its own directory rather than sharing one: tests that point the linter at a directory
    /// they do not own end up analysing whatever else is in it.
    private func makeMultiFileProject(named name: String) -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for index in 0..<12 {
            let source = """
            import SwiftUI

            struct View\(index): View {
                @State private var isLoading = false
                @State private var counter = 0
                let values: [String]? = nil

                var body: some View {
                    VStack {
                        Image("icon\(index)")
                        Text(values![0])
                        Button("Increment") { counter += 1 }
                        Image("badge\(index)")
                    }
                }
            }
            """
            try? source.write(
                to: root.appendingPathComponent("View\(index).swift"),
                atomically: true,
                encoding: .utf8
            )
        }
        return root.path
    }
}

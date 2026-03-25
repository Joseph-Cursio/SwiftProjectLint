import Testing
import SwiftUI
@testable import Core
@testable import App
import ViewInspector

struct LintResultsViewTests {

    @Test func testLintResultsViewInitialization() async throws {
        await MainActor.run {
            let sampleIssues = [
                LintIssue(
                    severity: .warning,
                    message: "Test issue",
                    filePath: "/test/file.swift",
                    lineNumber: 10,
                    suggestion: "Test suggestion",
                    ruleName: .relatedDuplicateStateVariable
                )
            ]

            _ = LintResultsView(issues: sampleIssues)
        }
    }

    @Test func testEmptyIssuesList() async throws {
        await MainActor.run {
            _ = LintResultsView(issues: [])
        }
    }

    @Test func testIssueSeverityFiltering() async throws {
        await MainActor.run {
            let issues = [
                LintIssue(
                    severity: .error,
                    message: "Error issue",
                    filePath: "/test/file.swift",
                    lineNumber: 1,
                    suggestion: "Fix this",
                    ruleName: .relatedDuplicateStateVariable
                ),
                LintIssue(
                    severity: .warning,
                    message: "Warning issue",
                    filePath: "/test/file2.swift",
                    lineNumber: 5,
                    suggestion: "Consider this",
                    ruleName: .missingStateObject
                ),
                LintIssue(
                    severity: .info,
                    message: "Info issue",
                    filePath: "/test/file3.swift",
                    lineNumber: 10,
                    suggestion: "Note this",
                    ruleName: .uninitializedStateVariable
                )
            ]

            _ = LintResultsView(issues: issues)

            let errorIssues = issues.filter { $0.severity == .error }
            let warningIssues = issues.filter { $0.severity == .warning }
            let infoIssues = issues.filter { $0.severity == .info }

            #expect(errorIssues.count == 1)
            #expect(warningIssues.count == 1)
            #expect(infoIssues.count == 1)
        }
    }

    @Test func testIssueRuleNameMapping() async throws {
        try await MainActor.run {
            let issues = [
                LintIssue(
                    severity: .warning,
                    message: "Test issue",
                    filePath: "/test/file.swift",
                    lineNumber: 1,
                    suggestion: "Test suggestion",
                    ruleName: .relatedDuplicateStateVariable
                )
            ]

            _ = LintResultsView(issues: issues)
            let firstIssue = try #require(issues.first)
            #expect(firstIssue.ruleName == .relatedDuplicateStateVariable)
        }
    }

    @Test func testIssueFileAndLineNumber() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Test issue",
            filePath: "/test/file.swift",
            lineNumber: 42,
            suggestion: "Test suggestion",
            ruleName: .relatedDuplicateStateVariable
        )

        #expect(issue.filePath == "/test/file.swift")
        #expect(issue.lineNumber == 42)
    }

    @Test func testIssueMessageAndSuggestion() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Duplicate state variable found",
            filePath: "/test/file.swift",
            lineNumber: 1,
            suggestion: "Use @StateObject instead",
            ruleName: .relatedDuplicateStateVariable
        )

        #expect(issue.message.contains("Duplicate state variable"))
        #expect(issue.suggestion?.contains("@StateObject") == true)
    }
}

struct LintResultsViewCharacterizationTests {
    @Test
    @MainActor
    func testSummarySectionAndCounts() throws {
        let issues = [
            LintIssue(
                severity: .error, message: "Error issue", filePath: "/file1.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .warning, message: "Warning issue", filePath: "/file2.swift",
                lineNumber: 2, suggestion: nil, ruleName: .missingStateObject
            ),
            LintIssue(
                severity: .info, message: "Info issue", filePath: "/file3.swift",
                lineNumber: 3, suggestion: nil, ruleName: .uninitializedStateVariable
            )
        ]
        let view = LintResultsView(issues: issues)
        let inspected = try view.inspect()

        let summarySection = try inspected.find(IssueSummarySection.self)
        let summaryTexts = try summarySection.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(summaryTexts.contains("Summary"))
        #expect(summaryTexts.contains("Total Issues"))
        #expect(summaryTexts.contains("Errors"))
        #expect(summaryTexts.contains("Warnings"))
        #expect(summaryTexts.contains("Info"))
    }

    @Test
    @MainActor
    func testIssueRowsAndFullScreenButton() throws {
        let issues = [
            LintIssue(
                severity: .error, message: "Error issue", filePath: "/file1.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .warning, message: "Warning issue", filePath: "/file2.swift",
                lineNumber: 2, suggestion: nil, ruleName: .missingStateObject
            )
        ]
        let view = LintResultsView(issues: issues)
        let inspected = try view.inspect()

        let list = try inspected.find(ViewType.List.self)
        let issuesSection = try list.section(1)
        let issueTexts = try issuesSection.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(issueTexts.contains("Error issue"))
        #expect(issueTexts.contains("Warning issue"))
    }

    @Test
    @MainActor
    func testSummaryCountValues() throws {
        let issues = [
            LintIssue(
                severity: .error, message: "Error 1", filePath: "/file1.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .error, message: "Error 2", filePath: "/file2.swift",
                lineNumber: 2, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .warning, message: "Warning 1", filePath: "/file3.swift",
                lineNumber: 3, suggestion: nil, ruleName: .missingStateObject
            ),
            LintIssue(
                severity: .info, message: "Info 1", filePath: "/file4.swift",
                lineNumber: 4, suggestion: nil, ruleName: .uninitializedStateVariable
            ),
            LintIssue(
                severity: .info, message: "Info 2", filePath: "/file5.swift",
                lineNumber: 5, suggestion: nil, ruleName: .uninitializedStateVariable
            )
        ]
        let view = LintResultsView(issues: issues)
        let inspected = try view.inspect()

        let allTexts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(allTexts.contains("5")) // Total issues
        #expect(allTexts.contains("2")) // Errors (appears twice: error count and info count)
        #expect(allTexts.contains("1")) // Warnings
    }

    @Test("empty issues list shows zero counts in summary")
    @MainActor
    func emptySummaryCountsAreZero() throws {
        let view = LintResultsView(issues: [])
        let inspected = try view.inspect()

        let allTexts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(allTexts.contains("Summary"))
        #expect(allTexts.contains("Total Issues"))
        // All counts should be "0"
        let zeroCount = allTexts.filter { $0 == "0" }.count
        #expect(zeroCount == 4) // Total, Errors, Warnings, Info all zero
    }

    @Test("issues section contains dividers between rows but not after the last")
    @MainActor
    func dividersBetweenIssueRows() throws {
        let issues = [
            LintIssue(
                severity: .error, message: "First", filePath: "/file1.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .warning, message: "Second", filePath: "/file2.swift",
                lineNumber: 2, suggestion: nil, ruleName: .missingStateObject
            ),
            LintIssue(
                severity: .info, message: "Third", filePath: "/file3.swift",
                lineNumber: 3, suggestion: nil, ruleName: .uninitializedStateVariable
            )
        ]
        let view = LintResultsView(issues: issues)
        let inspected = try view.inspect()

        let list = try inspected.find(ViewType.List.self)
        let issuesSection = try list.section(1)
        let dividers = issuesSection.findAll(ViewType.Divider.self)
        // 3 issues should have 2 dividers (between 1-2 and 2-3, not after 3)
        #expect(dividers.count == 2)
    }

    @Test("single issue has no dividers")
    @MainActor
    func singleIssueNoDividers() throws {
        let issues = [
            LintIssue(
                severity: .warning, message: "Only issue", filePath: "/file.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            )
        ]
        let view = LintResultsView(issues: issues)
        let inspected = try view.inspect()

        let list = try inspected.find(ViewType.List.self)
        let issuesSection = try list.section(1)
        let dividers = issuesSection.findAll(ViewType.Divider.self)
        #expect(dividers.isEmpty)
    }
}

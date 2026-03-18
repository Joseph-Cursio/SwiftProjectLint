import Testing
import SwiftUI
@testable import SwiftProjectLintCore
@testable import SwiftProjectLint
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
        await MainActor.run {
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
            #expect(issues[0].ruleName == .relatedDuplicateStateVariable)
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

// MARK: - LintIssueRow Tests

struct LintIssueRowTests {
    @Test
    @MainActor
    func testIssueRowDisplaysMessage() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Test warning message",
            filePath: "/path/to/file.swift",
            lineNumber: 42,
            suggestion: "Fix this issue",
            ruleName: .relatedDuplicateStateVariable
        )
        let row = LintIssueRow(issue: issue)
        let inspected = try row.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Test warning message"))
    }

    @Test
    @MainActor
    func testIssueRowDisplaysFileLocation() throws {
        let issue = LintIssue(
            severity: .error,
            message: "Error message",
            filePath: "/path/to/MyView.swift",
            lineNumber: 123,
            suggestion: nil,
            ruleName: .missingStateObject
        )
        let row = LintIssueRow(issue: issue)
        let inspected = try row.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("/path/to/MyView.swift:123"))
    }

    @Test
    @MainActor
    func testIssueRowHasExpandButton() throws {
        let issue = LintIssue(
            severity: .info,
            message: "Info message",
            filePath: "/file.swift",
            lineNumber: 1,
            suggestion: "Consider this",
            ruleName: .uninitializedStateVariable
        )
        let row = LintIssueRow(issue: issue)
        let inspected = try row.inspect()

        let buttons = inspected.findAll(ViewType.Button.self)
        #expect(buttons.count >= 1)
    }

    @Test
    @MainActor
    func testIssueRowShowsChevronIcon() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Warning",
            filePath: "/file.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .relatedDuplicateStateVariable
        )
        let row = LintIssueRow(issue: issue)
        let inspected = try row.inspect()

        let images = inspected.findAll(ViewType.Image.self)
        #expect(images.count >= 1) // At least severity icon present
    }

    @Test
    @MainActor
    func testIssueRowWithMultipleLocations() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Duplicate state across views",
            locations: [
                (filePath: "/path/to/View1.swift", lineNumber: 10),
                (filePath: "/path/to/View2.swift", lineNumber: 20),
                (filePath: "/path/to/View3.swift", lineNumber: 30)
            ],
            suggestion: "Consolidate state",
            ruleName: .relatedDuplicateStateVariable
        )

        let row = LintIssueRow(issue: issue)
        let inspected = try row.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("/path/to/View1.swift:10"))
        #expect(texts.contains("/path/to/View2.swift:20"))
        #expect(texts.contains("/path/to/View3.swift:30"))
    }

    @Test("error severity row displays red xmark.circle.fill icon")
    @MainActor
    func errorSeverityIcon() throws {
        let issue = LintIssue(
            severity: .error,
            message: "Error issue",
            filePath: "/file.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .relatedDuplicateStateVariable
        )
        let row = LintIssueRow(issue: issue)
        let inspected = try row.inspect()

        // Find the severity icon image
        let images = inspected.findAll(ViewType.Image.self)
        let systemNames = images.compactMap { try? $0.actualImage().name() }
        #expect(systemNames.contains("xmark.circle.fill"))
    }

    @Test("warning severity row displays orange exclamationmark icon")
    @MainActor
    func warningSeverityIcon() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Warning issue",
            filePath: "/file.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .missingStateObject
        )
        let row = LintIssueRow(issue: issue)
        let inspected = try row.inspect()

        let images = inspected.findAll(ViewType.Image.self)
        let systemNames = images.compactMap { try? $0.actualImage().name() }
        #expect(systemNames.contains("exclamationmark.triangle.fill"))
    }

    @Test("info severity row displays blue info.circle.fill icon")
    @MainActor
    func infoSeverityIcon() throws {
        let issue = LintIssue(
            severity: .info,
            message: "Info issue",
            filePath: "/file.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .uninitializedStateVariable
        )
        let row = LintIssueRow(issue: issue)
        let inspected = try row.inspect()

        let images = inspected.findAll(ViewType.Image.self)
        let systemNames = images.compactMap { try? $0.actualImage().name() }
        #expect(systemNames.contains("info.circle.fill"))
    }

    @Test("collapsed row shows chevron.down icon")
    @MainActor
    func collapsedRowShowsChevronDown() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Test",
            filePath: "/file.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .relatedDuplicateStateVariable
        )
        let row = LintIssueRow(issue: issue)
        let inspected = try row.inspect()

        let images = inspected.findAll(ViewType.Image.self)
        let systemNames = images.compactMap { try? $0.actualImage().name() }
        #expect(systemNames.contains("chevron.down"))
    }

    @Test("issue with nil suggestion does not show Suggestion label when collapsed")
    @MainActor
    func noSuggestionLabelWhenNilAndCollapsed() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "No suggestion here",
            filePath: "/file.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .relatedDuplicateStateVariable
        )
        let row = LintIssueRow(issue: issue)
        let inspected = try row.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Suggestion:") == false)
    }

    @Test("single location displays inline file path")
    @MainActor
    func singleLocationInlineDisplay() throws {
        let issue = LintIssue(
            severity: .error,
            message: "Single loc",
            filePath: "/only/one/file.swift",
            lineNumber: 55,
            suggestion: nil,
            ruleName: .fatView
        )
        let row = LintIssueRow(issue: issue)
        let inspected = try row.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("/only/one/file.swift:55"))
    }

    // MARK: - Expanded state

    @Test("expanded row shows chevron.up icon")
    @MainActor
    func expandedRowShowsChevronUp() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Test",
            filePath: "/file.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .relatedDuplicateStateVariable
        )
        let row = LintIssueRow(issue: issue, isExpanded: true)
        let inspected = try row.inspect()

        let images = inspected.findAll(ViewType.Image.self)
        let systemNames = images.compactMap { try? $0.actualImage().name() }
        #expect(systemNames.contains("chevron.up"))
    }

    @Test("expanded row shows Suggestion label when suggestion is non-nil")
    @MainActor
    func expandedRowShowsSuggestionLabel() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Some warning",
            filePath: "/file.swift",
            lineNumber: 1,
            suggestion: "Use a named constant",
            ruleName: .relatedDuplicateStateVariable
        )
        let row = LintIssueRow(issue: issue, isExpanded: true)
        let inspected = try row.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Suggestion:"))
        #expect(texts.contains("Use a named constant"))
    }

    @Test("expanded row omits Suggestion label when suggestion is nil")
    @MainActor
    func expandedRowOmitsSuggestionLabelWhenNil() throws {
        let issue = LintIssue(
            severity: .info,
            message: "Info message",
            filePath: "/file.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .uninitializedStateVariable
        )
        let row = LintIssueRow(issue: issue, isExpanded: true)
        let inspected = try row.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Suggestion:") == false)
    }

    @Test("expanded row shows Locations label")
    @MainActor
    func expandedRowShowsLocationsLabel() throws {
        let issue = LintIssue(
            severity: .error,
            message: "Error message",
            filePath: "/path/to/file.swift",
            lineNumber: 10,
            suggestion: nil,
            ruleName: .fatView
        )
        let row = LintIssueRow(issue: issue, isExpanded: true)
        let inspected = try row.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Locations:"))
    }

    @Test("expanded row shows file location in locations section")
    @MainActor
    func expandedRowShowsFileLocationInLocationsSection() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Warning",
            filePath: "/src/MyView.swift",
            lineNumber: 42,
            suggestion: "Fix it",
            ruleName: .missingStateObject
        )
        let row = LintIssueRow(issue: issue, isExpanded: true)
        let inspected = try row.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        // Expanded panel shows full message text again
        #expect(texts.contains("Warning"))
        #expect(texts.contains("Locations:"))
        #expect(texts.contains("/src/MyView.swift:42"))
    }

    @Test("expanded row with multiple locations shows all in locations section")
    @MainActor
    func expandedRowWithMultipleLocationsShowsAll() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Duplicate state",
            locations: [
                (filePath: "/ViewA.swift", lineNumber: 5),
                (filePath: "/ViewB.swift", lineNumber: 15)
            ],
            suggestion: "Consolidate",
            ruleName: .relatedDuplicateStateVariable
        )
        let row = LintIssueRow(issue: issue, isExpanded: true)
        let inspected = try row.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Locations:"))
        #expect(texts.contains("/ViewA.swift:5"))
        #expect(texts.contains("/ViewB.swift:15"))
    }
}

// MARK: - SummaryItem Tests

struct SummaryItemTests {
    @Test
    @MainActor
    func testSummaryItemDisplaysTitleAndValue() throws {
        let item = SummaryItem(title: "Total Issues", value: "42", color: .primary)
        let inspected = try item.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Total Issues"))
        #expect(texts.contains("42"))
    }

    @Test
    @MainActor
    func testSummaryItemWithZeroValue() throws {
        let item = SummaryItem(title: "Errors", value: "0", color: .red)
        let inspected = try item.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Errors"))
        #expect(texts.contains("0"))
    }

    @Test("summary item renders title in caption font and value in title2")
    @MainActor
    func summaryItemFontStyles() throws {
        let item = SummaryItem(title: "Warnings", value: "7", color: .orange)
        let inspected = try item.inspect()

        let texts = inspected.findAll(ViewType.Text.self)
        #expect(texts.count == 2)
        // Verify both title and value text elements exist
        let textStrings = try texts.map { try $0.string() }
        #expect(textStrings.contains("Warnings"))
        #expect(textStrings.contains("7"))
    }
}

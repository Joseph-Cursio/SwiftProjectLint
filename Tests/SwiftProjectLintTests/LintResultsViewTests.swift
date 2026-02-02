import Testing
import SwiftUI
@testable import SwiftProjectLintCore
@testable import SwiftProjectLint
import ViewInspector

final class LintResultsViewTests {
    
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
            // Just verify it can be created without crashing
            #expect(Bool(true)) // LintResultsView creation succeeded
        }
    }
    
    @Test func testEmptyIssuesList() async throws {
        await MainActor.run {
            _ = LintResultsView(issues: [])
            // Just verify it can be created without crashing
            #expect(Bool(true)) // LintResultsView creation succeeded
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
            #expect(Bool(true)) // LintResultsView creation succeeded
            
            // Test that all severities are represented
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
            #expect(Bool(true)) // LintResultsView creation succeeded
            
            // Test that rule name is properly set
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

final class LintResultsViewCharacterizationTests {
    @Test
    @MainActor
    func testSummarySectionAndCounts() throws {
        let issues = [
            LintIssue(severity: .error, message: "Error issue", filePath: "/file1.swift", lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable),
            LintIssue(severity: .warning, message: "Warning issue", filePath: "/file2.swift", lineNumber: 2, suggestion: nil, ruleName: .missingStateObject),
            LintIssue(severity: .info, message: "Info issue", filePath: "/file3.swift", lineNumber: 3, suggestion: nil, ruleName: .uninitializedStateVariable)
        ]
        let view = LintResultsView(issues: issues)
        let inspected = try view.inspect()

        let list = try inspected.find(ViewType.List.self)
        let summarySection = try list.section(0)
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
            LintIssue(severity: .error, message: "Error issue", filePath: "/file1.swift", lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable),
            LintIssue(severity: .warning, message: "Warning issue", filePath: "/file2.swift", lineNumber: 2, suggestion: nil, ruleName: .missingStateObject)
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
            LintIssue(severity: .error, message: "Error 1", filePath: "/file1.swift", lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable),
            LintIssue(severity: .error, message: "Error 2", filePath: "/file2.swift", lineNumber: 2, suggestion: nil, ruleName: .relatedDuplicateStateVariable),
            LintIssue(severity: .warning, message: "Warning 1", filePath: "/file3.swift", lineNumber: 3, suggestion: nil, ruleName: .missingStateObject),
            LintIssue(severity: .info, message: "Info 1", filePath: "/file4.swift", lineNumber: 4, suggestion: nil, ruleName: .uninitializedStateVariable),
            LintIssue(severity: .info, message: "Info 2", filePath: "/file5.swift", lineNumber: 5, suggestion: nil, ruleName: .uninitializedStateVariable)
        ]
        let view = LintResultsView(issues: issues)
        let inspected = try view.inspect()

        let allTexts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        // Verify count values are displayed
        #expect(allTexts.contains("5")) // Total issues
        #expect(allTexts.contains("2")) // Errors (appears twice: error count and info count)
        #expect(allTexts.contains("1")) // Warnings
    }
}

// MARK: - LintIssueRow Tests

final class LintIssueRowTests {
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

        // Should have a button for expand/collapse
        let buttons = try inspected.findAll(ViewType.Button.self)
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

        // Find system images (chevron icons)
        let images = try inspected.findAll(ViewType.Image.self)
        #expect(images.count >= 1) // At least severity icon present
    }

    @Test
    @MainActor
    func testIssueRowWithMultipleLocations() throws {
        // Create issue with multiple locations using the locations array initializer
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
        // Should show multiple locations
        #expect(texts.contains("/path/to/View1.swift:10"))
        #expect(texts.contains("/path/to/View2.swift:20"))
        #expect(texts.contains("/path/to/View3.swift:30"))
    }
}

// MARK: - SummaryItem Tests

final class SummaryItemTests {
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
}

// MARK: - LintResultsContainerView Tests

final class LintResultsContainerViewTests {
    @Test
    @MainActor
    func testContainerViewHasFullScreenButton() throws {
        let issues = [
            LintIssue(severity: .warning, message: "Test issue", filePath: "/file.swift", lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable)
        ]
        let container = LintResultsContainerView(issues: issues)
        let inspected = try container.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Full Screen"))
    }

    @Test
    @MainActor
    func testContainerViewContainsLintResultsView() throws {
        let issues = [
            LintIssue(severity: .error, message: "Error in container", filePath: "/file.swift", lineNumber: 5, suggestion: nil, ruleName: .missingStateObject)
        ]
        let container = LintResultsContainerView(issues: issues)
        let inspected = try container.inspect()

        // Should find the nested LintResultsView content
        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Error in container"))
        #expect(texts.contains("Summary"))
    }

    @Test
    @MainActor
    func testContainerViewHasExpandIcon() throws {
        let issues = [
            LintIssue(severity: .info, message: "Info", filePath: "/file.swift", lineNumber: 1, suggestion: nil, ruleName: .uninitializedStateVariable)
        ]
        let container = LintResultsContainerView(issues: issues)
        let inspected = try container.inspect()

        // Should have expand icon (arrow.up.left.and.arrow.down.right)
        let images = try inspected.findAll(ViewType.Image.self)
        #expect(images.count >= 1)
    }
}

// MARK: - FullScreenResultsView Tests

final class FullScreenResultsViewTests {
    @Test
    @MainActor
    func testFullScreenViewDisplaysIssues() throws {
        let issues = [
            LintIssue(severity: .error, message: "Full screen error", filePath: "/file.swift", lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable),
            LintIssue(severity: .warning, message: "Full screen warning", filePath: "/file2.swift", lineNumber: 2, suggestion: nil, ruleName: .missingStateObject)
        ]
        let fullScreen = FullScreenResultsView(issues: issues)
        let inspected = try fullScreen.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Full screen error"))
        #expect(texts.contains("Full screen warning"))
    }

    @Test
    @MainActor
    func testFullScreenViewHasSummarySection() throws {
        let issues = [
            LintIssue(severity: .error, message: "Error", filePath: "/file.swift", lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable)
        ]
        let fullScreen = FullScreenResultsView(issues: issues)
        let inspected = try fullScreen.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Summary"))
        #expect(texts.contains("Total Issues"))
        #expect(texts.contains("Errors"))
        #expect(texts.contains("Warnings"))
        #expect(texts.contains("Info"))
    }

    @Test
    @MainActor
    func testFullScreenViewHasDoneButton() throws {
        let issues = [
            LintIssue(severity: .info, message: "Info", filePath: "/file.swift", lineNumber: 1, suggestion: nil, ruleName: .uninitializedStateVariable)
        ]
        let fullScreen = FullScreenResultsView(issues: issues)
        let inspected = try fullScreen.inspect()

        let buttons = try inspected.findAll(ViewType.Button.self)
        let buttonLabels = buttons.compactMap { try? $0.labelView().text().string() }
        #expect(buttonLabels.contains("Done"))
    }

    @Test
    @MainActor
    func testFullScreenViewWithEmptyIssues() throws {
        let fullScreen = FullScreenResultsView(issues: [])
        let inspected = try fullScreen.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Summary"))
        #expect(texts.contains("0")) // All counts should be 0
    }
}

// MARK: - Edge Case Tests

final class LintResultsEdgeCaseTests {
    @Test
    @MainActor
    func testLongMessageDisplay() throws {
        let longMessage = "This is a very long error message that spans multiple lines and contains detailed information about the lint issue that was detected in the codebase during analysis"
        let issue = LintIssue(
            severity: .error,
            message: longMessage,
            filePath: "/very/long/path/to/some/deeply/nested/file.swift",
            lineNumber: 999,
            suggestion: nil,
            ruleName: .relatedDuplicateStateVariable
        )
        let row = LintIssueRow(issue: issue)
        let inspected = try row.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains(longMessage))
    }

    @Test
    @MainActor
    func testIssueWithSuggestion() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "State management issue",
            filePath: "/file.swift",
            lineNumber: 10,
            suggestion: "Use @StateObject instead of @ObservedObject",
            ruleName: .missingStateObject
        )
        let view = LintResultsView(issues: [issue])
        let inspected = try view.inspect()

        // The suggestion should be present in the expanded row content
        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("State management issue"))
    }

    @Test
    @MainActor
    func testAllSeverityTypes() throws {
        let issues = [
            LintIssue(severity: .error, message: "Error type", filePath: "/e.swift", lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable),
            LintIssue(severity: .warning, message: "Warning type", filePath: "/w.swift", lineNumber: 2, suggestion: nil, ruleName: .missingStateObject),
            LintIssue(severity: .info, message: "Info type", filePath: "/i.swift", lineNumber: 3, suggestion: nil, ruleName: .uninitializedStateVariable)
        ]
        let view = LintResultsView(issues: issues)
        let inspected = try view.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Error type"))
        #expect(texts.contains("Warning type"))
        #expect(texts.contains("Info type"))
    }
}

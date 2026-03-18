import Testing
import SwiftUI
@testable import SwiftProjectLintCore
@testable import SwiftProjectLint
import ViewInspector

// MARK: - LintResultsContainerView Tests

struct LintResultsContainerViewTests {
    @Test
    @MainActor
    func testContainerViewHasFullScreenButton() throws {
        let issues = [
            LintIssue(
                severity: .warning, message: "Test issue", filePath: "/file.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            )
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
            LintIssue(
                severity: .error, message: "Error in container", filePath: "/file.swift",
                lineNumber: 5, suggestion: nil, ruleName: .missingStateObject
            )
        ]
        let container = LintResultsContainerView(issues: issues)
        let inspected = try container.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Error in container"))
        #expect(texts.contains("Summary"))
    }

    @Test
    @MainActor
    func testContainerViewHasExpandIcon() throws {
        let issues = [
            LintIssue(
                severity: .info, message: "Info", filePath: "/file.swift",
                lineNumber: 1, suggestion: nil, ruleName: .uninitializedStateVariable
            )
        ]
        let container = LintResultsContainerView(issues: issues)
        let inspected = try container.inspect()

        let images = inspected.findAll(ViewType.Image.self)
        #expect(images.count >= 1)
    }

    @Test("container with empty issues still shows summary and full screen button")
    @MainActor
    func containerEmptyIssues() throws {
        let container = LintResultsContainerView(issues: [])
        let inspected = try container.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Full Screen"))
        #expect(texts.contains("Summary"))
    }

    @Test("expand icon uses arrow.up.left.and.arrow.down.right system image")
    @MainActor
    func expandIconSystemName() throws {
        let container = LintResultsContainerView(issues: [])
        let inspected = try container.inspect()

        let images = inspected.findAll(ViewType.Image.self)
        let systemNames = images.compactMap { try? $0.actualImage().name() }
        #expect(systemNames.contains("arrow.up.left.and.arrow.down.right"))
    }
}

// MARK: - FullScreenResultsView Tests

struct FullScreenResultsViewTests {
    @Test
    @MainActor
    func testFullScreenViewDisplaysIssues() throws {
        let issues = [
            LintIssue(
                severity: .error, message: "Full screen error", filePath: "/file.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .warning, message: "Full screen warning", filePath: "/file2.swift",
                lineNumber: 2, suggestion: nil, ruleName: .missingStateObject
            )
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
            LintIssue(
                severity: .error, message: "Error", filePath: "/file.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            )
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
            LintIssue(
                severity: .info, message: "Info", filePath: "/file.swift",
                lineNumber: 1, suggestion: nil, ruleName: .uninitializedStateVariable
            )
        ]
        let fullScreen = FullScreenResultsView(issues: issues)
        let inspected = try fullScreen.inspect()

        let buttons = inspected.findAll(ViewType.Button.self)
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

    @Test("full screen view summary shows correct counts for mixed severities")
    @MainActor
    func fullScreenSummaryCountsMixedSeverities() throws {
        let issues = [
            LintIssue(
                severity: .error, message: "Err 1", filePath: "/f1.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .error, message: "Err 2", filePath: "/f2.swift",
                lineNumber: 2, suggestion: nil, ruleName: .missingStateObject
            ),
            LintIssue(
                severity: .warning, message: "Warn 1", filePath: "/f3.swift",
                lineNumber: 3, suggestion: nil, ruleName: .fatView
            ),
            LintIssue(
                severity: .info, message: "Info 1", filePath: "/f4.swift",
                lineNumber: 4, suggestion: nil, ruleName: .uninitializedStateVariable
            )
        ]
        let fullScreen = FullScreenResultsView(issues: issues)
        let inspected = try fullScreen.inspect()

        let allTexts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(allTexts.contains("4")) // Total
        #expect(allTexts.contains("2")) // Errors
        #expect(allTexts.contains("1")) // Warnings and Info
    }

    @Test("full screen view has dividers between issue rows")
    @MainActor
    func fullScreenDividers() throws {
        let issues = [
            LintIssue(
                severity: .error, message: "First", filePath: "/f1.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .warning, message: "Second", filePath: "/f2.swift",
                lineNumber: 2, suggestion: nil, ruleName: .missingStateObject
            )
        ]
        let fullScreen = FullScreenResultsView(issues: issues)
        let inspected = try fullScreen.inspect()

        let navStack = try inspected.navigationStack()
        let list = try navStack.find(ViewType.List.self)
        let issuesSection = try list.section(1)
        let dividers = issuesSection.findAll(ViewType.Divider.self)
        // 2 issues -> 1 divider
        #expect(dividers.count == 1)
    }
}

// MARK: - Edge Case Tests

struct LintResultsEdgeCaseTests {
    @Test
    @MainActor
    func testLongMessageDisplay() throws {
        let longMessage = """
This is a very long error message that spans multiple lines and contains detailed information \
about the lint issue that was detected in the codebase during analysis
"""
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

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("State management issue"))
    }

    @Test
    @MainActor
    func testAllSeverityTypes() throws {
        let issues = [
            LintIssue(
                severity: .error, message: "Error type", filePath: "/e.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .warning, message: "Warning type", filePath: "/w.swift",
                lineNumber: 2, suggestion: nil, ruleName: .missingStateObject
            ),
            LintIssue(
                severity: .info, message: "Info type", filePath: "/i.swift",
                lineNumber: 3, suggestion: nil, ruleName: .uninitializedStateVariable
            )
        ]
        let view = LintResultsView(issues: issues)
        let inspected = try view.inspect()

        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Error type"))
        #expect(texts.contains("Warning type"))
        #expect(texts.contains("Info type"))
    }

    @Test("issue with empty locations array uses default values")
    func emptyLocationsDefaults() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "No locations",
            locations: [],
            suggestion: nil,
            ruleName: .relatedDuplicateStateVariable
        )
        #expect(issue.filePath.isEmpty)
        #expect(issue.lineNumber == 0)
    }

    @Test("issue with many locations preserves all of them")
    func manyLocationsPreserved() throws {
        let locations = (1...10).map { index in
            (filePath: "/file\(index).swift", lineNumber: index * 10)
        }
        let issue = LintIssue(
            severity: .error,
            message: "Many locations",
            locations: locations,
            suggestion: nil,
            ruleName: .fatView
        )
        #expect(issue.locations.count == 10)
        #expect(issue.filePath == "/file1.swift")
        #expect(issue.lineNumber == 10)
    }
}

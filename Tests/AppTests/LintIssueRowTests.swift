@testable import App
import SwiftProjectLintModels
import Testing
import ViewInspector

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
                (filePath: "/path/to/View3.swift", lineNumber: 30),
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
}

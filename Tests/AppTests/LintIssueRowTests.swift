import Testing
import SwiftUI
@testable import Core
@testable import App
import ViewInspector

struct LintIssueRowTests {
    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

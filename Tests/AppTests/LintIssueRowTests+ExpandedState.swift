@testable import App
@testable import Core
import Testing
import ViewInspector

extension LintIssueRowTests {
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
                (filePath: "/ViewB.swift", lineNumber: 15),
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

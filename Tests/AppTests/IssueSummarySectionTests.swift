import Testing
import SwiftUI
import ViewInspector
import SwiftProjectLintCore

@testable import SwiftProjectLint

@Suite("IssueSummarySection Tests")
@MainActor
struct IssueSummarySectionTests {

    @Test("displays all summary labels")
    func displaysAllLabels() throws {
        let view = IssueSummarySection(issues: [])
        let inspected = try view.inspect()
        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("Summary"))
        #expect(texts.contains("Total Issues"))
        #expect(texts.contains("Errors"))
        #expect(texts.contains("Warnings"))
        #expect(texts.contains("Info"))
    }

    @Test("empty issues shows all zeros")
    func emptyIssuesShowsZeros() throws {
        let view = IssueSummarySection(issues: [])
        let inspected = try view.inspect()
        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        let zeroCount = texts.filter { $0 == "0" }.count
        #expect(zeroCount == 4) // Total, Errors, Warnings, Info
    }

    @Test("counts match mixed severity issues")
    func countsMixedSeverities() throws {
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
            )
        ]
        let view = IssueSummarySection(issues: issues)
        let inspected = try view.inspect()
        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("4")) // Total
        #expect(texts.contains("2")) // Errors
        #expect(texts.contains("1")) // Warnings and Info
    }

    @Test("single severity type shows correct counts")
    func singleSeverityType() throws {
        let issues = [
            LintIssue(
                severity: .warning, message: "Warn 1", filePath: "/file1.swift",
                lineNumber: 1, suggestion: nil, ruleName: .missingStateObject
            ),
            LintIssue(
                severity: .warning, message: "Warn 2", filePath: "/file2.swift",
                lineNumber: 2, suggestion: nil, ruleName: .missingStateObject
            ),
            LintIssue(
                severity: .warning, message: "Warn 3", filePath: "/file3.swift",
                lineNumber: 3, suggestion: nil, ruleName: .missingStateObject
            )
        ]
        let view = IssueSummarySection(issues: issues)
        let inspected = try view.inspect()
        let texts = try inspected.findAll(ViewType.Text.self).map { try $0.string() }
        #expect(texts.contains("3")) // Total and Warnings
        // Errors and Info should be 0
        let zeroCount = texts.filter { $0 == "0" }.count
        #expect(zeroCount == 2) // Errors and Info
    }

    @Test("renders four SummaryItem components")
    func rendersFourSummaryItems() throws {
        let view = IssueSummarySection(issues: [])
        let inspected = try view.inspect()
        let items = inspected.findAll(SummaryItem.self)
        #expect(items.count == 4)
    }
}

import Foundation
import Testing
import Core
@testable import CLI

struct CSVFormatterTests {
    @Test
    func producesCSVWithHeader() {
        let csv = CSVFormatter().format(issues: [])
        let lines = csv.components(separatedBy: "\n")

        #expect(lines[0] == "Rule,Category,File Path,Line,Severity,Message,Suggestion")
    }

    @Test
    func formatsIssueAsCSVRow() {
        let issue = LintIssue(
            severity: .warning,
            message: "Test issue",
            filePath: "View.swift",
            lineNumber: 5,
            suggestion: "Fix it",
            ruleName: .fatView
        )
        let csv = CSVFormatter().format(issues: [issue])
        let lines = csv.components(separatedBy: "\n")

        #expect(lines.count == 3) // header + 1 row + trailing newline
        #expect(lines[1].contains("View.swift"))
        #expect(lines[1].contains("warning"))
        #expect(lines[1].contains("Test issue"))
        #expect(lines[1].contains("Fix it"))
    }

    @Test
    func escapesCommasInMessages() {
        let issue = LintIssue(
            severity: .error,
            message: "Error in file, line, and column",
            filePath: "Test.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .forceTry
        )
        let csv = CSVFormatter().format(issues: [issue])

        // Message with commas should be quoted
        #expect(csv.contains("\"Error in file, line, and column\""))
    }

    @Test
    func handlesMultipleLocations() {
        let issue = LintIssue(
            severity: .info,
            message: "Duplicate state",
            locations: [
                (filePath: "A.swift", lineNumber: 10),
                (filePath: "B.swift", lineNumber: 20)
            ],
            suggestion: nil,
            ruleName: .relatedDuplicateStateVariable
        )
        let csv = CSVFormatter().format(issues: [issue])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }

        // Header + 2 rows (one per location)
        #expect(lines.count == 3)
        #expect(lines[1].contains("A.swift"))
        #expect(lines[2].contains("B.swift"))
    }

    @Test
    func handlesEmptyIssues() {
        let csv = CSVFormatter().format(issues: [])
        let lines = csv.components(separatedBy: "\n").filter { !$0.isEmpty }

        #expect(lines.count == 1) // header only
    }

    @Test
    func omitsSuggestionWhenNil() {
        let issue = LintIssue(
            severity: .warning,
            message: "No suggestion",
            filePath: "X.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .fatView
        )
        let csv = CSVFormatter().format(issues: [issue])
        let lines = csv.components(separatedBy: "\n")

        // Last field should be empty (no suggestion)
        #expect(lines[1].hasSuffix(","))
    }
}

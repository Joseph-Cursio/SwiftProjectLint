import Testing
import SwiftProjectLintCore
@testable import SwiftProjectLintCLI

@Suite
struct TextFormatterTests {
    @Test
    func formatsSingleIssue() {
        let issue = LintIssue(
            severity: .warning,
            message: "Consider extracting this logic",
            filePath: "MyView.swift",
            lineNumber: 42,
            suggestion: "Move to a ViewModel",
            ruleName: .fatView
        )
        let output = TextFormatter.format(issues: [issue])
        #expect(output.contains("MyView.swift:42: warning: [Fat View] Consider extracting this logic"))
        #expect(output.contains("  suggestion: Move to a ViewModel"))
        #expect(output.contains("Found 1 issue (1 warning)"))
    }

    @Test
    func formatsMultipleSeverities() {
        let issues = [
            LintIssue(severity: .error, message: "err", filePath: "A.swift",
                       lineNumber: 1, suggestion: nil, ruleName: .fatView),
            LintIssue(severity: .warning, message: "warn", filePath: "B.swift",
                       lineNumber: 2, suggestion: nil, ruleName: .fatView),
            LintIssue(severity: .info, message: "note", filePath: "C.swift",
                       lineNumber: 3, suggestion: nil, ruleName: .fatView)
        ]
        let summary = TextFormatter.summaryLine(for: issues)
        #expect(summary == "Found 3 issues (1 error, 1 warning, 1 info)")
    }

    @Test
    func formatsEmptyIssues() {
        let output = TextFormatter.format(issues: [])
        #expect(output.contains("No issues found."))
    }

    @Test
    func omitsSuggestionWhenNil() {
        let issue = LintIssue(
            severity: .info,
            message: "test message",
            filePath: "Test.swift",
            lineNumber: 10,
            suggestion: nil,
            ruleName: .fatView
        )
        let output = TextFormatter.format(issues: [issue])
        #expect(!output.contains("suggestion:"))
    }
}

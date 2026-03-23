import Foundation
import Testing
import Core
@testable import CLI

struct JSONFormatterTests {
    @Test
    func producesValidJSON() throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Test issue",
            filePath: "View.swift",
            lineNumber: 5,
            suggestion: "Fix it",
            ruleName: .fatView
        )
        let jsonString = JSONFormatter.format(issues: [issue])
        let data = try #require(jsonString.data(using: .utf8))
        let decoded = try JSONDecoder().decode(LintReport.self, from: data)
        #expect(decoded.summary.totalIssues == 1)
        #expect(decoded.summary.warningCount == 1)
        #expect(decoded.summary.errorCount == 0)
        #expect(decoded.issues.count == 1)
        #expect(decoded.issues[0].severity == "warning")
        #expect(decoded.issues[0].message == "Test issue")
        #expect(decoded.issues[0].suggestion == "Fix it")
        #expect(decoded.issues[0].locations[0].filePath == "View.swift")
        #expect(decoded.issues[0].locations[0].lineNumber == 5)
    }

    @Test
    func handlesEmptyIssues() throws {
        let jsonString = JSONFormatter.format(issues: [])
        let data = try #require(jsonString.data(using: .utf8))
        let decoded = try JSONDecoder().decode(LintReport.self, from: data)
        #expect(decoded.summary.totalIssues == 0)
        #expect(decoded.issues.isEmpty)
    }

    @Test
    func includesCategory() throws {
        let issue = LintIssue(
            severity: .error,
            message: "test",
            filePath: "A.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .fatView
        )
        let jsonString = JSONFormatter.format(issues: [issue])
        let data = try #require(jsonString.data(using: .utf8))
        let decoded = try JSONDecoder().decode(LintReport.self, from: data)
        #expect(decoded.issues[0].category.isEmpty == false)

    }
}

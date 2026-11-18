import Core
import Foundation
import Testing

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
        let jsonString = JSONFormatter().format(issues: [issue])
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
        let jsonString = JSONFormatter().format(issues: [])
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
        let jsonString = JSONFormatter().format(issues: [issue])
        let data = try #require(jsonString.data(using: .utf8))
        let decoded = try JSONDecoder().decode(LintReport.self, from: data)
        #expect(decoded.issues[0].category.isEmpty == false)
    }
}

struct JSONReportSchemaTests {
    private static func decode(_ issues: [LintIssue]) throws -> LintReport {
        let data = try #require(JSONFormatter().format(issues: issues).data(using: .utf8))
        return try JSONDecoder().decode(LintReport.self, from: data)
    }

    private static func issue(_ rule: RuleIdentifier) -> LintIssue {
        LintIssue(severity: .info, message: "m", filePath: "A.swift", lineNumber: 1, suggestion: nil, ruleName: rule)
    }

    @Test
    func reportCarriesSchemaVersionAndTool() throws {
        let report = try Self.decode([])
        #expect(report.schemaVersion == LintReport.currentSchemaVersion)
        #expect(report.schemaVersion == 1)
        #expect(report.tool.name == "SwiftProjectLint")
        #expect(report.tool.version == SwiftProjectLintVersion.current)
    }

    @Test
    func issuesCarryCaseNameAndKind() throws {
        let report = try Self.decode([Self.issue(.forceUnwrap), Self.issue(.pureFunctionCandidate)])
        #expect(report.issues.map(\.ruleName) == ["Force Unwrap", "Pure Function Property-Test Candidate"])
        #expect(report.issues.map(\.ruleIdentifier) == ["forceUnwrap", "pureFunctionCandidate"])
        #expect(report.issues.map(\.kind) == [.defect, .census])
    }

    @Test
    func jsonSpellsTheNewKeys() throws {
        let json = JSONFormatter().format(issues: [Self.issue(.impureClosureInventory)])
        #expect(json.contains("\"schemaVersion\" : 1"))
        #expect(json.contains("\"ruleIdentifier\" : \"impureClosureInventory\""))
        #expect(json.contains("\"kind\" : \"census\""))
        #expect(json.contains("\"version\" : \"\(SwiftProjectLintVersion.current)\""))
    }
}

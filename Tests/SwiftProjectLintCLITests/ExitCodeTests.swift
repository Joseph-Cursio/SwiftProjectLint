import Testing
import SwiftProjectLintCore
@testable import SwiftProjectLintCLI

@Suite
struct ExitCodeTests {
    @Test
    func cleanWhenNoIssues() {
        let code = ExitCodes.exitCode(for: [], threshold: .warning)
        #expect(code == 0)
    }

    @Test
    func errorsReturnTwo() {
        let issues = [
            LintIssue(severity: .error, message: "err", filePath: "A.swift",
                       lineNumber: 1, suggestion: nil, ruleName: .fatView)
        ]
        #expect(ExitCodes.exitCode(for: issues, threshold: .warning) == 2)
        #expect(ExitCodes.exitCode(for: issues, threshold: .error) == 2)
        #expect(ExitCodes.exitCode(for: issues, threshold: .info) == 2)
    }

    @Test
    func warningsReturnOneWithWarningThreshold() {
        let issues = [
            LintIssue(severity: .warning, message: "warn", filePath: "A.swift",
                       lineNumber: 1, suggestion: nil, ruleName: .fatView)
        ]
        #expect(ExitCodes.exitCode(for: issues, threshold: .warning) == 1)
    }

    @Test
    func warningsCleanWithErrorThreshold() {
        let issues = [
            LintIssue(severity: .warning, message: "warn", filePath: "A.swift",
                       lineNumber: 1, suggestion: nil, ruleName: .fatView)
        ]
        #expect(ExitCodes.exitCode(for: issues, threshold: .error) == 0)
    }

    @Test
    func infoCleanWithWarningThreshold() {
        let issues = [
            LintIssue(severity: .info, message: "info", filePath: "A.swift",
                       lineNumber: 1, suggestion: nil, ruleName: .fatView)
        ]
        #expect(ExitCodes.exitCode(for: issues, threshold: .warning) == 0)
    }

    @Test
    func infoTriggersWithInfoThreshold() {
        let issues = [
            LintIssue(severity: .info, message: "info", filePath: "A.swift",
                       lineNumber: 1, suggestion: nil, ruleName: .fatView)
        ]
        #expect(ExitCodes.exitCode(for: issues, threshold: .info) == 1)
    }
}

import Testing
import Core
@testable import CLI

@Suite
struct ExitCodeTests {
    // swiftprojectlint:disable Test Missing Require
    @Test
    func cleanWhenNoIssues() {
        let code = ExitCodes.exitCode(for: [], threshold: .warning)
        #expect(code == 0)
    }

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
    @Test
    func warningsReturnOneWithWarningThreshold() {
        let issues = [
            LintIssue(severity: .warning, message: "warn", filePath: "A.swift",
                      lineNumber: 1, suggestion: nil, ruleName: .fatView)
        ]
        #expect(ExitCodes.exitCode(for: issues, threshold: .warning) == 1)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func warningsCleanWithErrorThreshold() {
        let issues = [
            LintIssue(severity: .warning, message: "warn", filePath: "A.swift",
                      lineNumber: 1, suggestion: nil, ruleName: .fatView)
        ]
        #expect(ExitCodes.exitCode(for: issues, threshold: .error) == 0)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func infoCleanWithWarningThreshold() {
        let issues = [
            LintIssue(severity: .info, message: "info", filePath: "A.swift",
                      lineNumber: 1, suggestion: nil, ruleName: .fatView)
        ]
        #expect(ExitCodes.exitCode(for: issues, threshold: .warning) == 0)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func infoTriggersWithInfoThreshold() {
        let issues = [
            LintIssue(severity: .info, message: "info", filePath: "A.swift",
                      lineNumber: 1, suggestion: nil, ruleName: .fatView)
        ]
        #expect(ExitCodes.exitCode(for: issues, threshold: .info) == 1)
    }
}

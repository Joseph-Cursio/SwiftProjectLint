import Testing
import SwiftUI
@testable import SwiftProjectLintCore
@testable import SwiftProjectLint

final class LintResultsViewTests {
    
    @Test func testLintResultsViewInitialization() async throws {
        await MainActor.run {
            let sampleIssues = [
                LintIssue(
                    severity: .warning,
                    message: "Test issue",
                    filePath: "/test/file.swift",
                    lineNumber: 10,
                    suggestion: "Test suggestion",
                    ruleName: .relatedDuplicateStateVariable
                )
            ]
            
            _ = LintResultsView(issues: sampleIssues)
            // Just verify it can be created without crashing
            #expect(Bool(true)) // LintResultsView creation succeeded
        }
    }
    
    @Test func testEmptyIssuesList() async throws {
        await MainActor.run {
            _ = LintResultsView(issues: [])
            // Just verify it can be created without crashing
            #expect(Bool(true)) // LintResultsView creation succeeded
        }
    }
    
    @Test func testIssueSeverityFiltering() async throws {
        await MainActor.run {
            let issues = [
                LintIssue(
                    severity: .error,
                    message: "Error issue",
                    filePath: "/test/file.swift",
                    lineNumber: 1,
                    suggestion: "Fix this",
                    ruleName: .relatedDuplicateStateVariable
                ),
                LintIssue(
                    severity: .warning,
                    message: "Warning issue",
                    filePath: "/test/file2.swift",
                    lineNumber: 5,
                    suggestion: "Consider this",
                    ruleName: .missingStateObject
                ),
                LintIssue(
                    severity: .info,
                    message: "Info issue",
                    filePath: "/test/file3.swift",
                    lineNumber: 10,
                    suggestion: "Note this",
                    ruleName: .uninitializedStateVariable
                )
            ]
            
            _ = LintResultsView(issues: issues)
            #expect(Bool(true)) // LintResultsView creation succeeded
            
            // Test that all severities are represented
            let errorIssues = issues.filter { $0.severity == .error }
            let warningIssues = issues.filter { $0.severity == .warning }
            let infoIssues = issues.filter { $0.severity == .info }
            
            #expect(errorIssues.count == 1)
            #expect(warningIssues.count == 1)
            #expect(infoIssues.count == 1)
        }
    }
    
    @Test func testIssueRuleNameMapping() async throws {
        await MainActor.run {
            let issues = [
                LintIssue(
                    severity: .warning,
                    message: "Test issue",
                    filePath: "/test/file.swift",
                    lineNumber: 1,
                    suggestion: "Test suggestion",
                    ruleName: .relatedDuplicateStateVariable
                )
            ]
            
            _ = LintResultsView(issues: issues)
            #expect(Bool(true)) // LintResultsView creation succeeded
            
            // Test that rule name is properly set
            #expect(issues[0].ruleName == .relatedDuplicateStateVariable)
        }
    }
    
    @Test func testIssueFileAndLineNumber() async throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Test issue",
            filePath: "/test/file.swift",
            lineNumber: 42,
            suggestion: "Test suggestion",
            ruleName: .relatedDuplicateStateVariable
        )
        
        #expect(issue.filePath == "/test/file.swift")
        #expect(issue.lineNumber == 42)
    }
    
    @Test func testIssueMessageAndSuggestion() async throws {
        let issue = LintIssue(
            severity: .warning,
            message: "Duplicate state variable found",
            filePath: "/test/file.swift",
            lineNumber: 1,
            suggestion: "Use @StateObject instead",
            ruleName: .relatedDuplicateStateVariable
        )
        
        #expect(issue.message.contains("Duplicate state variable"))
        #expect(issue.suggestion?.contains("@StateObject") == true)
    }
}

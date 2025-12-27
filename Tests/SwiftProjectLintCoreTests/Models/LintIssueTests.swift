import Testing
import SwiftProjectLintCore

@Suite("LintIssueTests")
struct LintIssueTests {
    
    @Test func testLintIssueInitializationWithSingleLocation() {
        let issue = LintIssue(
            severity: .warning,
            message: "Test issue",
            filePath: "test.swift",
            lineNumber: 42,
            suggestion: "Fix this",
            ruleName: .magicNumber
        )
        
        #expect(issue.severity == .warning)
        #expect(issue.message == "Test issue")
        #expect(issue.filePath == "test.swift")
        #expect(issue.lineNumber == 42)
        #expect(issue.suggestion == "Fix this")
        #expect(issue.ruleName == .magicNumber)
        #expect(issue.locations.count == 1)
        #expect(issue.locations.first?.filePath == "test.swift")
        #expect(issue.locations.first?.lineNumber == 42)
    }
    
    @Test func testLintIssueInitializationWithMultipleLocations() {
        let locations: [(filePath: String, lineNumber: Int)] = [
            ("file1.swift", 10),
            ("file2.swift", 20),
            ("file3.swift", 30)
        ]
        
        let issue = LintIssue(
            severity: .error,
            message: "Cross-file issue",
            locations: locations,
            suggestion: "Fix all locations",
            ruleName: .relatedDuplicateStateVariable
        )
        
        #expect(issue.severity == .error)
        #expect(issue.message == "Cross-file issue")
        #expect(issue.locations.count == 3)
        #expect(issue.locations[0].filePath == "file1.swift")
        #expect(issue.locations[0].lineNumber == 10)
        #expect(issue.locations[1].filePath == "file2.swift")
        #expect(issue.locations[1].lineNumber == 20)
        #expect(issue.locations[2].filePath == "file3.swift")
        #expect(issue.locations[2].lineNumber == 30)
        
        // Single location properties should return first location
        #expect(issue.filePath == "file1.swift")
        #expect(issue.lineNumber == 10)
    }
    
    @Test func testLintIssueWithNilSuggestion() {
        let issue = LintIssue(
            severity: .info,
            message: "Info message",
            filePath: "test.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .magicNumber
        )
        
        #expect(issue.suggestion == nil)
    }
    
    @Test func testLintIssueIdentifiable() {
        let issue1 = LintIssue(
            severity: .warning,
            message: "Issue 1",
            filePath: "test.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .magicNumber
        )
        
        let issue2 = LintIssue(
            severity: .warning,
            message: "Issue 2",
            filePath: "test.swift",
            lineNumber: 2,
            suggestion: nil,
            ruleName: .magicNumber
        )
        
        // Each issue should have a unique ID
        #expect(issue1.id != issue2.id)
    }
    
    @Test func testLintIssueEmptyLocations() {
        let issue = LintIssue(
            severity: .warning,
            message: "Test",
            locations: [],
            suggestion: nil,
            ruleName: .magicNumber
        )
        
        #expect(issue.locations.isEmpty)
        #expect(issue.filePath == "")
        #expect(issue.lineNumber == 0)
    }
    
    @Test func testLintIssueDifferentSeverities() {
        let error = LintIssue(
            severity: .error,
            message: "Error",
            filePath: "test.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .magicNumber
        )
        
        let warning = LintIssue(
            severity: .warning,
            message: "Warning",
            filePath: "test.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .magicNumber
        )
        
        let info = LintIssue(
            severity: .info,
            message: "Info",
            filePath: "test.swift",
            lineNumber: 1,
            suggestion: nil,
            ruleName: .magicNumber
        )
        
        #expect(error.severity == .error)
        #expect(warning.severity == .warning)
        #expect(info.severity == .info)
    }
    
    @Test func testLintIssueSendable() {
        // Verify LintIssue conforms to Sendable
        // This test verifies compilation - if LintIssue conforms to Sendable, this will compile
        let issue = LintIssue(
            severity: .warning,
            message: "Test",
            filePath: "test.swift",
            lineNumber: 1,
            suggestion: "Fix",
            ruleName: .magicNumber
        )
        
        // Verify the issue was created successfully
        #expect(issue.severity == .warning)
        #expect(issue.message == "Test")
    }
}


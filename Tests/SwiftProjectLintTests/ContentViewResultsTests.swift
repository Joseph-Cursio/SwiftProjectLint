import Testing
import SwiftUI
import ViewInspector
import SwiftProjectLintCore

@testable import SwiftProjectLint

@Suite
@MainActor
struct ContentViewResultsTests {
    @Test
    func testResultsNotShownWhenNoIssues() throws {
        let view = ContentViewResults(lintIssues: [], isAnalyzing: false)
        // Should render nothing
        #expect((try? view.inspect().vStack()) == nil)
    }

    @Test
    func testResultsNotShownWhenAnalyzing() throws {
        let demoIssues = [
            LintIssue(severity: .warning, message: "Demo", filePath: "Test.swift", lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable)
        ]
        let view = ContentViewResults(lintIssues: demoIssues, isAnalyzing: true)
        // Should render nothing
        #expect((try? view.inspect().vStack()) == nil)
    }

    @Test
    func testResultsShownWhenIssuesAndNotAnalyzing() throws {
        let demoIssues = [
            LintIssue(severity: .warning, message: "Demo", filePath: "Test.swift", lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable),
            LintIssue(severity: .error, message: "Another", filePath: "Test2.swift", lineNumber: 2, suggestion: nil, ruleName: .missingStateObject)
        ]
        let view = ContentViewResults(lintIssues: demoIssues, isAnalyzing: false)
        let inspected = try view.inspect()
        let vStack = try inspected.vStack()
        // Header
        let hStack = try vStack.hStack(0)
        #expect(try hStack.text(0).string() == "Analysis Results")
        #expect(try hStack.text(2).string() == "2 issues found")
        // LintResultsView
        _ = try vStack.find(LintResultsView.self)
    }
} 

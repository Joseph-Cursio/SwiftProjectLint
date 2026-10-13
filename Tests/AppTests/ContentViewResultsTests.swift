import Core
import SwiftUI
import Testing
import ViewInspector

@testable import App

@Suite
@MainActor
struct ContentViewResultsTests {
    @Test
    func testResultsNotShownWhenNoIssues() {
        let view = ContentViewResults(lintIssues: [], isAnalyzing: false)
        // Should render nothing
        #expect((try? view.inspect().vStack()) == nil)
    }

    @Test
    func testResultsNotShownWhenAnalyzing() {
        let demoIssues = [
            LintIssue(
                severity: .warning, message: "Demo", filePath: "Test.swift", lineNumber: 1,
                suggestion: nil, ruleName: .relatedDuplicateStateVariable
            )
        ]
        let view = ContentViewResults(lintIssues: demoIssues, isAnalyzing: true)
        // Should render nothing
        #expect((try? view.inspect().vStack()) == nil)
    }

    @Test
    func testResultsShownWhenIssuesAndNotAnalyzing() throws {
        let demoIssues = [
            LintIssue(
                severity: .warning, message: "Demo", filePath: "Test.swift", lineNumber: 1,
                suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .error, message: "Another", filePath: "Test2.swift", lineNumber: 2,
                suggestion: nil, ruleName: .missingStateObject
            )
        ]
        let view = ContentViewResults(lintIssues: demoIssues, isAnalyzing: false)
        let inspected = try view.inspect()
        #expect(try inspected.resultsTitle() == "Analysis Results")
        #expect(try inspected.resultsCount() == "2 issues found")
        _ = try inspected.find(LintResultsView.self)
    }
}

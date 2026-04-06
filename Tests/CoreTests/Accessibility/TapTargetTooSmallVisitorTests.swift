import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct TapTargetTooSmallVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = TapTargetTooSmallVisitor(patternCategory: .accessibility)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .tapTargetTooSmall }
    }

    // MARK: - Positive: flags small tap targets

    @Test func testFlagsSmallButton() throws {
        let source = """
        Button(action: { dismiss() }) {
            Image(systemName: "xmark")
        }
        .frame(width: 30, height: 30)
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("30"))
        #expect(issue.message.contains("44"))
    }

    @Test func testFlagsOneDimensionBelow() throws {
        let source = """
        Button("OK") { }
            .frame(width: 44, height: 20)
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsToggle() throws {
        let source = """
        Toggle(isOn: .constant(true)) { Text("Flag") }
            .frame(width: 30, height: 30)
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsNavigationLink() throws {
        let source = """
        NavigationLink(destination: DetailView()) {
            Image(systemName: "chevron.right")
        }
        .frame(width: 20, height: 20)
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForMeetsMinimum() throws {
        let source = """
        Button(action: {}) {
            Image(systemName: "xmark")
        }
        .frame(width: 44, height: 44)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForLargerThanMinimum() throws {
        let source = """
        Button("Submit") { }
            .frame(width: 200, height: 50)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithPadding() throws {
        let source = """
        Button(action: {}) {
            Image(systemName: "xmark")
        }
        .frame(width: 20, height: 20)
        .padding()
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForOnlyWidthSet() throws {
        let source = """
        Button("OK") { }
            .frame(width: 30)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNonInteractiveElement() throws {
        let source = """
        Text("Hello")
            .frame(width: 20, height: 20)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForImageFrame() throws {
        let source = """
        Image(systemName: "star")
            .frame(width: 20, height: 20)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

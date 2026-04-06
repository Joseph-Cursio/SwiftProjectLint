import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct LegacyReplacingOccurrencesVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = LegacyReplacingOccurrencesVisitor(patternCategory: .modernization)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .legacyReplacingOccurrences }
    }

    // MARK: - Positive: flags replacingOccurrences(of:with:)

    @Test func testFlagsSimpleReplacingOccurrences() throws {
        let source = """
        let result = str.replacingOccurrences(of: "hello", with: "world")
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("replacingOccurrences"))
    }

    @Test func testFlagsChainedReplacingOccurrences() throws {
        let source = """
        let result = path
            .replacingOccurrences(of: "\\\\", with: "/")
            .replacingOccurrences(of: " ", with: "_")
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
    }

    @Test func testFlagsReplacingOccurrencesInFunction() throws {
        let source = """
        func clean(_ input: String) -> String {
            return input.replacingOccurrences(of: "bad", with: "good")
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForModernReplacing() throws {
        let source = """
        let result = str.replacing("hello", with: "world")
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedMethod() throws {
        let source = """
        let result = arr.replacing([1, 2], with: [3, 4])
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForOtherMemberAccess() throws {
        let source = """
        let count = str.count
        let upper = str.uppercased()
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

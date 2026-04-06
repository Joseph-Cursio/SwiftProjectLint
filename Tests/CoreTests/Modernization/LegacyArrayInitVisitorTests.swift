import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct LegacyArrayInitVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = LegacyArrayInitVisitor(patternCategory: .modernization)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .legacyArrayInit }
    }

    // MARK: - Positive: flags verbose initializers

    @Test func testFlagsArrayInit() throws {
        let source = """
        let items = Array<String>()
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("Array<String>"))
        #expect(issue.message.contains("[String]"))
    }

    @Test func testFlagsDictionaryInit() throws {
        let source = """
        let map = Dictionary<String, Int>()
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Dictionary") == true)
    }

    @Test func testFlagsOptionalNone() throws {
        let source = """
        let nothing = Optional<String>.none
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("nil") == true)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForShorthandArray() throws {
        let source = """
        let items: [String] = []
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForShorthandDictionary() throws {
        let source = """
        let map: [String: Int] = [:]
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForArrayWithArguments() throws {
        let source = """
        let items = Array<Int>(repeating: 0, count: 10)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForSetInit() throws {
        let source = """
        let unique = Set<String>()
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNil() throws {
        let source = """
        let nothing: String? = nil
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedCode() throws {
        let source = """
        let name = String(describing: type)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

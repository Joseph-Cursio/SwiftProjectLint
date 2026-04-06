import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct LegacyClosureSyntaxVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = LegacyClosureSyntaxVisitor(patternCategory: .modernization)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .legacyClosureSyntax }
    }

    // MARK: - Positive: flags redundant type annotations

    @Test func testFlagsExplicitTypesInMap() throws {
        let source = """
        let names = users.map { (user: User) -> String in
            return user.name
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("inferred"))
    }

    @Test func testFlagsExplicitTypesInFilter() throws {
        let source = """
        let adults = users.filter { (user: User) -> Bool in
            user.age >= 18
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsExplicitTypesInSorted() throws {
        let source = """
        let sorted = items.sorted { (lhs: Item, rhs: Item) -> Bool in
            lhs.date < rhs.date
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsExplicitTypesInForEach() throws {
        let source = """
        items.forEach { (item: Item) in
            process(item)
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForInferredTypes() throws {
        let source = """
        let names = users.map { user in user.name }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForShorthandSyntax() throws {
        let source = """
        let names = users.map { $0.name }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNonInferrableContext() throws {
        let source = """
        let closure = { (value: Int) -> String in
            String(value)
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForCustomFunction() throws {
        let source = """
        doWork { (result: Result) in
            handle(result)
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedCode() throws {
        let source = """
        let count = items.count
        let first = items.first
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

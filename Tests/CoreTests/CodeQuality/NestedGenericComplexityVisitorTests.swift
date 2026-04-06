import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct NestedGenericComplexityVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = NestedGenericComplexityVisitor(patternCategory: .codeQuality)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .nestedGenericComplexity }
    }

    // MARK: - Positive: flags complex generics

    @Test func testFlagsFourGenericParameters() throws {
        let source = """
        func transform<Input, Output, Intermediate, Extra>(
            _ input: Input
        ) -> Output { fatalError() }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.message.contains("4"))
        #expect(issue.message.contains("type parameters"))
    }

    @Test func testFlagsDeeplyNestedGenericArguments() throws {
        let source = """
        var result: Result<Array<Optional<String>>, Error>
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("nesting depth") == true)
    }

    @Test func testFlagsComplexWhereClause() throws {
        let source = """
        func process<TypeVar>(_ val: TypeVar)
            where TypeVar: Equatable, TypeVar: Hashable,
                  TypeVar: Codable, TypeVar: Sendable { }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("where clause") == true)
    }

    @Test func testFlagsFiveGenericParameters() throws {
        let source = """
        func combine<ParamA, ParamB, ParamC, ParamD, ParamE>() { }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("5") == true)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForTwoParameters() throws {
        let source = """
        func map<Input, Output>(_ transform: (Input) -> Output) -> [Output] { [] }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForThreeParameters() throws {
        let source = """
        func zip<ParamA, ParamB, ParamC>(_ first: ParamA, _ second: ParamB, _ third: ParamC) { }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForShallowNesting() throws {
        let source = """
        var result: Result<[String], Error>
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForThreeWhereConstraints() throws {
        let source = """
        func process<TypeVar>(_ val: TypeVar) where TypeVar: Equatable, TypeVar: Hashable, TypeVar: Codable { }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForSimpleGenericType() throws {
        let source = """
        var items: Array<String>
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

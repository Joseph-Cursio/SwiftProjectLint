@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct GlobalMutableStateVisitorTests {

    private func analyze(_ source: String, filePath: String = "TestFile.swift") -> [LintIssue] {
        let visitor = GlobalMutableStateVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .globalMutableState }
    }

    @Test func flagsTopLevelVar() throws {
        let issue = try #require(analyze("var counter = 0").first)
        #expect(issue.ruleName == .globalMutableState)
        #expect(issue.severity == .warning)
    }

    @Test func flagsStaticVar() {
        let source = """
        enum Config {
            static var shared = 0
        }
        """
        #expect(analyze(source).count == 1)
    }

    @Test func ignoresTopLevelLet() {
        #expect(analyze("let counter = 0").isEmpty)
    }

    @Test func ignoresStaticLet() {
        #expect(analyze("enum Config { static let shared = 0 }").isEmpty)
    }

    @Test func ignoresInstanceVar() {
        // Instance stored properties are normal state, not global.
        #expect(analyze("struct Model { var value = 0 }").isEmpty)
    }

    @Test func ignoresComputedStaticVar() {
        let source = """
        enum Config {
            static var value: Int { 42 }
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresTopLevelComputedVar() {
        #expect(analyze("var value: Int { 42 }").isEmpty)
    }
}

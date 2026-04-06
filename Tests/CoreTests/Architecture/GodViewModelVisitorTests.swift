import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct GodViewModelVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = GodViewModelVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .godViewModel }
    }

    // MARK: - Positive: flags god view models

    @Test func testFlagsObservableObjectWith11Published() throws {
        let props = (1...11).map { "    @Published var prop\($0): String = \"\"" }
            .joined(separator: "\n")
        let source = """
        class BigViewModel: ObservableObject {
        \(props)
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("BigViewModel"))
        #expect(issue.message.contains("11"))
    }

    @Test func testFlagsObservableWith16Vars() throws {
        let props = (1...16).map { "    var prop\($0): String = \"\"" }
            .joined(separator: "\n")
        let source = """
        @Observable
        class LargeModel {
        \(props)
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.message.contains("LargeModel"))
        #expect(issue.message.contains("16"))
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForSmallObservableObject() throws {
        let source = """
        class AuthViewModel: ObservableObject {
            @Published var email: String = ""
            @Published var password: String = ""
            @Published var isLoading: Bool = false
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueAtExactThreshold() throws {
        let props = (1...10).map { "    @Published var prop\($0): String = \"\"" }
            .joined(separator: "\n")
        let source = """
        class ExactViewModel: ObservableObject {
        \(props)
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForObservableAtThreshold() throws {
        let props = (1...15).map { "    var prop\($0): String = \"\"" }
            .joined(separator: "\n")
        let source = """
        @Observable
        class OkModel {
        \(props)
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNonViewModel() throws {
        let props = (1...20).map { "    var prop\($0): String = \"\"" }
            .joined(separator: "\n")
        let source = """
        class PlainClass {
        \(props)
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testExcludesComputedProperties() throws {
        let stored = (1...8).map { "    var prop\($0): String = \"\"" }
            .joined(separator: "\n")
        let computed = (1...10).map {
            "    var computed\($0): String { \"val\" }"
        }.joined(separator: "\n")
        let source = """
        @Observable
        class MixedModel {
        \(stored)
        \(computed)
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForStruct() throws {
        let props = (1...20).map { "    @Published var prop\($0): String = \"\"" }
            .joined(separator: "\n")
        let source = """
        struct BigStruct: ObservableObject {
        \(props)
        }
        """
        let issues = filteredIssues(source)
        // Structs can't conform to ObservableObject, but the visitor only checks classes
        #expect(issues.isEmpty)
    }
}

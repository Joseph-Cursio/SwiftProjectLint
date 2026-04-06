import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct ArchitectureComputedPropertyViewTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = ComputedPropertyViewVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .computedPropertyView }
    }

    // MARK: - Positive: flags computed properties returning some View

    @Test func testFlagsComputedPropertyReturningView() throws {
        let source = """
        struct ContentView: View {
            var header: some View {
                Text("Title")
            }
            var body: some View {
                header
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.message.contains("header"))
        #expect(issue.severity == .warning)
    }

    @Test func testFlagsMultipleComputedProperties() throws {
        let source = """
        struct MyView: View {
            var header: some View { Text("H") }
            var footer: some View { Text("F") }
            var body: some View {
                VStack { header; footer }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
        let names = issues.compactMap { $0.message }
        #expect(names.contains(where: { $0.contains("header") }))
        #expect(names.contains(where: { $0.contains("footer") }))
    }

    @Test func testViewBuilderPropertyFlaggedAsInfo() throws {
        let source = """
        struct MyView: View {
            @ViewBuilder
            var content: some View {
                Text("Hello")
            }
            var body: some View { content }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("@ViewBuilder"))
    }

    @Test func testDetectsViewViaBodyHeuristic() throws {
        let source = """
        struct CustomView {
            var body: some View {
                Text("Body")
            }
            var sidebar: some View {
                Text("Side")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("sidebar") == true)
    }

    // MARK: - Negative: should NOT flag

    @Test func testBodyPropertyNotFlagged() throws {
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNonViewTypeNotFlagged() throws {
        let source = """
        struct Utility {
            var helper: some View {
                Text("Not in a View type")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testStoredPropertyNotFlagged() throws {
        let source = """
        struct MyView: View {
            var title: String = "Hello"
            var body: some View {
                Text(title)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testClassConformingToView() throws {
        let source = """
        class MyViewController: View {
            var header: some View {
                Text("Title")
            }
            var body: some View {
                header
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("header") == true)
    }

    @Test func testComputedPropertyReturningNonView() throws {
        let source = """
        struct MyView: View {
            var title: String { "Hello" }
            var body: some View {
                Text(title)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

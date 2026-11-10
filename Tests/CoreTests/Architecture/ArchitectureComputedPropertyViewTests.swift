import Foundation
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

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
    //
    // Each fixture below carries a stored input the flagged property does not read. That is not
    // decoration: the rule reports a property only when extracting it would give the child a
    // narrower input surface than its parent, so a view with no inputs at all has nothing to
    // narrow and is deliberately silent. The gate itself is specified in its own suite at the
    // bottom of this file.

    @Test func testFlagsComputedPropertyReturningView() throws {
        let source = """
        struct ContentView: View {
            let title: String
            var header: some View {
                Text("Title")
            }
            var body: some View {
                VStack { header; Text(title) }
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.message.contains("header"))
        #expect(issue.severity == .warning)
    }

    @Test func testFlagsMultipleComputedProperties() {
        let source = """
        struct MyView: View {
            let title: String
            var header: some View { Text("H") }
            var footer: some View { Text("F") }
            var body: some View {
                VStack { header; footer; Text(title) }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
        let names = issues.compactMap(\.message)
        #expect(names.contains { $0.contains("header") })
        #expect(names.contains { $0.contains("footer") })
    }

    @Test func testViewBuilderPropertyFlaggedAsInfo() throws {
        let source = """
        struct MyView: View {
            let title: String
            @ViewBuilder
            var content: some View {
                Text("Hello")
            }
            var body: some View { VStack { content; Text(title) } }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("@ViewBuilder"))
    }

    @Test func testDetectsViewViaBodyHeuristic() {
        let source = """
        struct CustomView {
            let title: String
            var body: some View {
                VStack { sidebar; Text(title) }
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

    @Test func testBodyPropertyNotFlagged() {
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

    @Test func testNonViewTypeNotFlagged() {
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

    @Test func testStoredPropertyNotFlagged() {
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

    @Test func testClassConformingToView() {
        let source = """
        class MyViewController: View {
            let title: String
            var header: some View {
                Text("Title")
            }
            var body: some View {
                VStack { header; Text(title) }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("header") == true)
    }

    @Test func testComputedPropertyReturningNonView() {
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

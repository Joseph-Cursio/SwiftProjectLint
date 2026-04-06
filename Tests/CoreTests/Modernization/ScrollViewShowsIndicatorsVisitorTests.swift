import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct ScrollViewShowsIndicatorsVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = ScrollViewShowsIndicatorsVisitor(patternCategory: .modernization)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .scrollViewShowsIndicators }
    }

    // MARK: - Positive: flags showsIndicators

    @Test func testFlagsShowsIndicatorsFalse() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                ScrollView(.vertical, showsIndicators: false) {
                    Text("Content")
                }
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("showsIndicators"))
    }

    @Test func testFlagsShowsIndicatorsTrue() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                ScrollView(showsIndicators: true) {
                    Text("Content")
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForModernScrollIndicators() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                ScrollView(.vertical) {
                    Text("Content")
                }
                .scrollIndicators(.hidden)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForPlainScrollView() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                ScrollView {
                    Text("Content")
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedViews() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                List { Text("Item") }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

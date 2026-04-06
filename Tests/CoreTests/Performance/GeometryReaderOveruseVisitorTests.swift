import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct GeometryReaderOveruseVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = GeometryReaderOveruseVisitor(patternCategory: .performance)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .geometryReaderOveruse }
    }

    // MARK: - Positive: flags GeometryReader

    @Test func testFlagsGeometryReader() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                GeometryReader { geometry in
                    Text("Hello")
                        .frame(width: geometry.size.width * 0.8)
                }
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("GeometryReader"))
    }

    @Test func testFlagsMultipleGeometryReaders() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    GeometryReader { geo in Text("A") }
                    GeometryReader { geo in Text("B") }
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForContainerRelativeFrame() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .containerRelativeFrame(.horizontal) { length, _ in
                        length * 0.8
                    }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForVisualEffect() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .visualEffect { content, proxy in
                        content.offset(y: proxy.frame(in: .global).minY)
                    }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedCode() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack { Text("Hello") }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

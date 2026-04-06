import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct MissingDynamicTypeSupportVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = MissingDynamicTypeSupportVisitor(patternCategory: .accessibility)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .missingDynamicTypeSupport }
    }

    // MARK: - Positive: flags lineLimit(1) on dynamic text

    @Test func testFlagsLineLimitOnVariableText() throws {
        let source = """
        struct MyView: View {
            let title: String
            var body: some View {
                Text(title)
                    .lineLimit(1)
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("lineLimit"))
    }

    @Test func testFlagsLineLimitOnMemberAccess() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text(article.title)
                    .lineLimit(1)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsLineLimitOnInterpolation() throws {
        let source = """
        struct MyView: View {
            let name: String
            var body: some View {
                Text("Welcome, \\(name)!")
                    .lineLimit(1)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsLineLimitOnFunctionCallArg() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text(formattedDate())
                    .lineLimit(1)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForShortStaticLabel() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Save")
                    .lineLimit(1)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithMinimumScaleFactor() throws {
        let source = """
        struct MyView: View {
            let title: String
            var body: some View {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForLineLimitZero() throws {
        let source = """
        struct MyView: View {
            let title: String
            var body: some View {
                Text(title)
                    .lineLimit(0)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForLineLimitGreaterThanOne() throws {
        let source = """
        struct MyView: View {
            let title: String
            var body: some View {
                Text(title)
                    .lineLimit(3)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNonTextElement() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack { }
                    .lineLimit(1)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithoutLineLimit() throws {
        let source = """
        struct MyView: View {
            let title: String
            var body: some View {
                Text(title)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

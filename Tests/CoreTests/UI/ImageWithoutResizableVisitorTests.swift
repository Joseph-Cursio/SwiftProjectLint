import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct ImageWithoutResizableVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = ImageWithoutResizableVisitor(patternCategory: .uiPatterns)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .imageWithoutResizable }
    }

    // MARK: - Positive: flags Image with frame but no resizable

    @Test func testFlagsImageWithFrameNoResizable() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("hero")
                    .frame(width: 200, height: 100)
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("resizable"))
    }

    @Test func testFlagsSFSymbolWithFrameNoResizable() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image(systemName: "star.fill")
                    .frame(width: 50, height: 50)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsImageWithModifiersButNoResizable() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("photo")
                    .clipShape(Circle())
                    .frame(width: 100, height: 100)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueWithResizableBeforeFrame() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("hero")
                    .resizable()
                    .frame(width: 200, height: 100)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithResizableAndAspectRatio() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("hero")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForImageWithoutFrame() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("hero")
                    .resizable()
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNonImageWithFrame() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .frame(width: 200, height: 100)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForPlainImage() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("hero")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

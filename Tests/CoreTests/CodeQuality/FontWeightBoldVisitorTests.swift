import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct FontWeightBoldVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = FontWeightBoldVisitor(patternCategory: .codeQuality)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .fontWeightBold }
    }

    // MARK: - Positive: flags .fontWeight(.bold)

    @Test func testFlagsFontWeightBold() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello").fontWeight(.bold)
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains(".bold()"))
    }

    @Test func testFlagsMultipleFontWeightBold() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("One").fontWeight(.bold)
                    Text("Two").fontWeight(.bold)
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForBoldModifier() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello").bold()
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForOtherFontWeights() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("A").fontWeight(.semibold)
                    Text("B").fontWeight(.heavy)
                    Text("C").fontWeight(.light)
                    Text("D").fontWeight(.medium)
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedModifiers() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello").font(.title).padding()
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

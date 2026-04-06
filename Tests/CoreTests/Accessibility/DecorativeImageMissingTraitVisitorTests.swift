import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct DecorativeImageMissingTraitVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = DecorativeImageMissingTraitVisitor(patternCategory: .accessibility)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .decorativeImageMissingTrait }
    }

    // MARK: - Positive: flags decorative images without accessibility

    @Test func testFlagsDecorativeNamedImage() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("headerBackground")
                    .resizable()
                    .frame(height: 200)
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("headerBackground"))
    }

    @Test func testFlagsImageWithLowOpacity() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("gradient")
                    .opacity(0.3)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsPatternImage() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("tilePattern")
                    .resizable()
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueWithAccessibilityHidden() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("headerBackground")
                    .resizable()
                    .accessibilityHidden(true)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithAccessibilityLabel() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("chart")
                    .accessibilityLabel("Sales chart")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForSFSymbol() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image(systemName: "star.fill")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNonDecorativeName() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("profilePhoto")
                    .resizable()
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueInsideButton() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Button { } label: {
                    Image("backgroundTexture")
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForFullOpacity() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("hero")
                    .opacity(1.0)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

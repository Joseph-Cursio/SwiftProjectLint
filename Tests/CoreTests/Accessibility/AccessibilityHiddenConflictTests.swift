import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct AccessibilityHiddenConflictTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "MyView.swift"
    ) -> [LintIssue] {
        let visitor = AccessibilityHiddenConflictVisitor(patternCategory: .accessibility)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .accessibilityHiddenConflict }
    }

    // MARK: - Positive: flags conflicting modifiers

    @Test func testFlagsHiddenWithLabel() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("icon")
                    .accessibilityHidden(true)
                    .accessibilityLabel("Send")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("accessibilityLabel"))
    }

    @Test func testFlagsHiddenWithHint() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Button("Tap") { action() }
                    .accessibilityHidden(true)
                    .accessibilityHint("Does something")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("accessibilityHint") == true)
    }

    @Test func testFlagsHiddenWithMultipleConflicts() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                HStack { Text("Hello") }
                    .accessibilityHidden(true)
                    .accessibilityLabel("Greeting")
                    .accessibilityHint("A greeting")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        let message = try #require(issues.first?.message)
        #expect(message.contains("accessibilityLabel"))
        #expect(message.contains("accessibilityHint"))
    }

    @Test func testFlagsHiddenWithAddTraits() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Header")
                    .accessibilityHidden(true)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsHiddenWithValue() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Slider(value: .constant(5))
                    .accessibilityHidden(true)
                    .accessibilityValue("5 out of 10")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testReportsOnlyOncePerChain() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("icon")
                    .accessibilityHidden(true)
                    .accessibilityLabel("Send")
                    .accessibilityHint("Sends email")
            }
        }
        """
        let issues = filteredIssues(source)
        // Should be exactly 1 issue, not one per modifier
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForHiddenAlone() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("background")
                    .accessibilityHidden(true)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForHiddenWithNonAccessibilityModifiers() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("background")
                    .accessibilityHidden(true)
                    .padding()
                    .frame(width: 100)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForLabelWithoutHidden() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("icon")
                    .accessibilityLabel("Send")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForIgnoreWithLabel() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                HStack {
                    Image(systemName: "star")
                    Text("Favorite")
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Favorite")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testSkipsTestFiles() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Image("icon")
                    .accessibilityHidden(true)
                    .accessibilityLabel("Send")
            }
        }
        """
        let issues = analyzeSource(source, filePath: "MyViewTests.swift")
            .filter { $0.ruleName == .accessibilityHiddenConflict }
        #expect(issues.isEmpty)
    }
}

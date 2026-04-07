import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct StackAccessibilityGroupingTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "MyView.swift"
    ) -> [LintIssue] {
        let visitor = StackAccessibilityGroupingVisitor(patternCategory: .accessibility)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .stackMissingAccessibilityGrouping }
    }

    // MARK: - Positive: flags stacks with two Text children

    @Test func testFlagsVStackWithTwoTexts() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Temperature")
                    Text("72F")
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("VStack"))
    }

    @Test func testFlagsHStackWithTwoTexts() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                HStack {
                    Text("Status")
                    Text("Online")
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("HStack"))
    }

    @Test func testFlagsMultipleUngroupedStacks() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                HStack {
                    VStack {
                        Text("Core temperature")
                        Text("1,000,000C")
                    }
                    VStack {
                        Text("Outside temperature")
                        Text("-178C")
                    }
                }
            }
        }
        """
        let issues = filteredIssues(source)
        // Both inner VStacks should be flagged, not the outer HStack
        #expect(issues.count == 2)
    }

    @Test func testFlagsStackWithModifiedTexts() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Label")
                        .font(.caption)
                    Text("Value")
                        .bold()
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueWithAccessibilityElement() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Temperature")
                    Text("72F")
                }
                .accessibilityElement(children: .combine)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithAccessibilityHidden() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Debug")
                    Text("v1.2.3")
                }
                .accessibilityHidden(true)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithInteractiveElement() throws {
        let source = """
        struct MyView: View {
            @State private var enabled = false
            var body: some View {
                HStack {
                    Text("Notifications")
                    Toggle("", isOn: $enabled)
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithButton() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Delete")
                    Button("Confirm") { delete() }
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithSingleText() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Hello")
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithThreeTexts() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Title")
                    Text("Subtitle")
                    Text("Detail")
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForZStack() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                ZStack {
                    Text("Background")
                    Text("Foreground")
                }
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
                VStack {
                    Text("Label")
                    Text("Value")
                }
            }
        }
        """
        let issues = analyzeSource(source, filePath: "MyViewTests.swift")
            .filter { $0.ruleName == .stackMissingAccessibilityGrouping }
        #expect(issues.isEmpty)
    }
}

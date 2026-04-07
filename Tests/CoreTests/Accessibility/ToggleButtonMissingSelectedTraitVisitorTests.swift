import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct ToggleButtonSelectedTraitTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "MyView.swift"
    ) -> [LintIssue] {
        let visitor = ToggleButtonMissingSelectedTraitVisitor(patternCategory: .accessibility)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .toggleButtonMissingSelectedTrait }
    }

    // MARK: - Positive: flags buttons with ternary but no traits

    @Test func testFlagsButtonWithTernaryInTrailingClosure() throws {
        let source = """
        struct MyView: View {
            @State private var selected = false
            var body: some View {
                Button(action: { selected.toggle() }) {
                    Image(systemName: selected ? "circle.fill" : "circle")
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("accessibilityAddTraits"))
    }

    @Test func testFlagsButtonWithTernaryInLabelArgument() throws {
        let source = """
        struct MyView: View {
            @State private var active = false
            var body: some View {
                Button {
                    active.toggle()
                } label: {
                    Text(active ? "On" : "Off")
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsButtonWithNestedTernary() throws {
        let source = """
        struct MyView: View {
            @State private var selected = false
            var body: some View {
                Button(action: { selected.toggle() }) {
                    HStack {
                        Image(systemName: selected ? "star.fill" : "star")
                        Text("Favorite")
                    }
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueWhenAccessibilityAddTraitsPresent() throws {
        let source = """
        struct MyView: View {
            @State private var selected = false
            var body: some View {
                Button(action: { selected.toggle() }) {
                    Image(systemName: selected ? "circle.fill" : "circle")
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWhenAccessibilityHidden() throws {
        let source = """
        struct MyView: View {
            @State private var selected = false
            var body: some View {
                Button(action: { selected.toggle() }) {
                    Image(systemName: selected ? "circle.fill" : "circle")
                }
                .accessibilityHidden(true)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForButtonWithoutTernary() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Button("Submit") {
                    submitForm()
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNonButtonWithTernary() throws {
        let source = """
        struct MyView: View {
            @State private var active = false
            var body: some View {
                Text(active ? "On" : "Off")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testSkipsTestFiles() throws {
        let source = """
        struct MyViewTests: View {
            @State private var selected = false
            var body: some View {
                Button(action: { selected.toggle() }) {
                    Image(systemName: selected ? "circle.fill" : "circle")
                }
            }
        }
        """
        let issues = analyzeSource(source, filePath: "MyViewTests.swift")
            .filter { $0.ruleName == .toggleButtonMissingSelectedTrait }
        #expect(issues.isEmpty)
    }
}

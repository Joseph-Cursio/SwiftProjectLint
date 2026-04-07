import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct SortPriorityWithoutContainerTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "MyView.swift"
    ) -> [LintIssue] {
        let visitor = SortPriorityWithoutContainerVisitor(patternCategory: .accessibility)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .sortPriorityWithoutContainer }
    }

    // MARK: - Positive: flags sort priority without container

    @Test func testFlagsVStackWithoutContainer() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Last").accessibilitySortPriority(0)
                    Text("First").accessibilitySortPriority(2)
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
        let issue = try #require(issues.first)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("VStack"))
    }

    @Test func testFlagsHStackWithoutContainer() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                HStack {
                    Text("Second").accessibilitySortPriority(1)
                    Text("First").accessibilitySortPriority(2)
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
        #expect(issues.first?.message.contains("HStack") == true)
    }

    @Test func testFlagsZStackWithoutContainer() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                ZStack {
                    Text("Back").accessibilitySortPriority(0)
                    Text("Front").accessibilitySortPriority(1)
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
    }

    @Test func testFlagsSingleSortPriority() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Important").accessibilitySortPriority(1)
                    Text("Normal")
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueWithContainModifier() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Last").accessibilitySortPriority(0)
                    Text("First").accessibilitySortPriority(2)
                }
                .accessibilityElement(children: .contain)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithCombineModifier() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Last").accessibilitySortPriority(0)
                    Text("First").accessibilitySortPriority(2)
                }
                .accessibilityElement(children: .combine)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueWithoutSortPriority() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                VStack {
                    Text("Hello")
                    Text("World")
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueOutsideStack() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .accessibilitySortPriority(1)
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
                    Text("Last").accessibilitySortPriority(0)
                    Text("First").accessibilitySortPriority(2)
                }
            }
        }
        """
        let issues = analyzeSource(source, filePath: "MyViewTests.swift")
            .filter { $0.ruleName == .sortPriorityWithoutContainer }
        #expect(issues.isEmpty)
    }
}

import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct TabItemDeprecatedVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = TabItemDeprecatedVisitor(patternCategory: .modernization)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .tabItemDeprecated }
    }

    // MARK: - Positive: flags .tabItem

    @Test func testFlagsTabItemModifier() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                TabView {
                    Text("Home")
                        .tabItem {
                            Label("Home", systemImage: "house")
                        }
                }
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("tabItem"))
    }

    @Test func testFlagsMultipleTabItems() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                TabView {
                    Text("Home")
                        .tabItem { Label("Home", systemImage: "house") }
                    Text("Settings")
                        .tabItem { Label("Settings", systemImage: "gear") }
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForModernTabAPI() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                TabView {
                    Tab("Home", systemImage: "house") {
                        Text("Home")
                    }
                }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedModifier() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text("Hello")
                    .padding()
                    .font(.title)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

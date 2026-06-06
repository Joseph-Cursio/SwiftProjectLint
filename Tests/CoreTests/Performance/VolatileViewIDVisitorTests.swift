@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct VolatileViewIDVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = VolatileViewIDVisitor(patternCategory: .performance)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .volatileViewID }
    }

    // MARK: - Positive cases

    @Test func testFlagsListIDBoundToReassignedUUIDToken() throws {
        let source = """
        struct RulesView: View {
            @State private var listRefreshToken = UUID()
            var body: some View {
                Button("Select All") { listRefreshToken = UUID() }
                List(rules) { rule in RuleRow(rule) }
                    .id(listRefreshToken)
            }
        }
        """
        let issues = analyzeSource(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("listRefreshToken"))
    }

    @Test func testFlagsIncrementedCounterToken() {
        let source = """
        struct TreeView: View {
            @State private var version = 0
            var body: some View {
                Button("Refresh") { version += 1 }
                ScrollView { content }.id(version)
            }
        }
        """
        #expect(analyzeSource(source).count == 1)
    }

    @Test func testFlagsSelfQualifiedToken() {
        let source = """
        struct SomeView: View {
            @State private var token = UUID()
            func bump() { self.token = UUID() }
            var body: some View {
                List { rows }.id(self.token)
            }
        }
        """
        #expect(analyzeSource(source).count == 1)
    }

    @Test func testFlagsEachVolatileIDSite() {
        let source = """
        struct SomeView: View {
            @State private var token = UUID()
            var body: some View {
                Button("Reset") { token = UUID() }
                VStack {
                    List { a }.id(token)
                    List { b }.id(token)
                }
            }
        }
        """
        #expect(analyzeSource(source).count == 2)
    }

    // MARK: - Negative cases (no false positives)

    @Test func testStableIDIsNotFlagged() {
        // `sectionKind` is never reassigned — this is the legitimate use of .id.
        let source = """
        struct SomeView: View {
            let sectionKind: Kind
            var body: some View {
                List { rows }.id(sectionKind)
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func testKeypathMemberIDIsNotFlagged() {
        // `.id(item.id)` is per-element identity, not an identity-churn hack.
        let source = """
        struct SomeView: View {
            @State private var item = Item()
            var body: some View {
                Button("Change") { item = Item() }
                RowView().id(item.id)
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }

    @Test func testComparisonOperatorDoesNotCountAsMutation() {
        // `token == other` must not mark `token` as reassigned.
        let source = """
        struct SomeView: View {
            let token = UUID()
            var body: some View {
                if token == other { EmptyView() }
                List { rows }.id(token)
            }
        }
        """
        #expect(analyzeSource(source).isEmpty)
    }
}

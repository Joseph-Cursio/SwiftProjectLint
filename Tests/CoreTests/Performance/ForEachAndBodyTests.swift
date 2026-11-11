import Foundation
import SwiftParser
import SwiftProjectLintEngine
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Tests for PerformanceVisitor ForEach and view body size detection
@Suite
struct ForEachAndBodyTests {

    // MARK: - Helper Methods

    func createVisitor() -> PerformanceVisitor {
        PerformanceVisitor(patternCategory: .performance)
    }

    func analyzeSource(
        _ source: String,
        filePath: String = "TestView.swift",
        identifiableTypes: Set<String> = [],
        identifiableCollectionProperties: Set<String> = []
    ) -> [LintIssue] {
        let visitor = createVisitor()
        visitor.knownIdentifiableTypes = identifiableTypes
        visitor.knownIdentifiableCollectionProperties = identifiableCollectionProperties
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    // MARK: - ForEach Without ID Tests

    /// `insights` is declared on the view model, in another file; the pre-scan's catalog says
    /// every `insights` property in the project is an array of an Identifiable type.
    @Test func testNoForEachWithoutIDForIdentifiableMemberDeclaredElsewhere() {
        let source = """
        struct Sidebar: View {
            let viewModel: DiagramViewModel
            var body: some View {
                List { ForEach(viewModel.insights) { insight in Text(insight.title) } }
            }
        }
        """
        let issues = analyzeSource(source, identifiableCollectionProperties: ["insights"])
        #expect(issues.contains { $0.ruleName == .forEachWithoutID } == false)
    }

    /// Through the whole linter: the pre-scan reads `insights` and `history` from the view
    /// model's file, and `DiagramEntity` is Identifiable through SwiftData's `@Model`.
    @Test func testProjectLinterKnowsIdentifiableMembersFromOtherFiles() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForEachCrossFile-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            "Insight.swift": "struct Insight: Identifiable { let id: UUID; let title: String }",
            "DiagramEntity.swift": "@Model final class DiagramEntity { var name: String = \"\" }",
            "DiagramViewModel.swift": """
            @Observable final class DiagramViewModel {
                var insights: [Insight] = []
                var history: [DiagramEntity] = []
                var names: [String] = []
            }
            """,
            "Sidebar.swift": """
            struct Sidebar: View {
                let viewModel: DiagramViewModel
                var body: some View {
                    List {
                        ForEach(viewModel.insights) { insight in Text(insight.title) }
                        ForEach(viewModel.history) { entity in Text(entity.name) }
                        ForEach(viewModel.names) { name in Text(name) }
                    }
                }
            }
            """,
        ]
        for (name, source) in files {
            try? source.write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await ProjectLinter().analyzeProject(
            at: root.path, ruleIdentifiers: [.forEachWithoutID], detector: system.detector
        )
        // Only `names`, an array of String.
        #expect(issues.map(\.lineNumber) == [7])
    }

    @Test func testForEachWithoutIDForMemberNotInTheCatalog() {
        let source = """
        struct Sidebar: View {
            let viewModel: DiagramViewModel
            var body: some View {
                List { ForEach(viewModel.names) { name in Text(name) } }
            }
        }
        """
        let issues = analyzeSource(source, identifiableCollectionProperties: ["insights"])
        #expect(issues.filter { $0.ruleName == .forEachWithoutID }.count == 1)
    }

    @Test func testDetectsForEachWithoutID() throws {
        let source = """
        struct TestView: View {
            @State private var items = [1, 2, 3]

            var body: some View {
                VStack {
                    ForEach(items) { item in
                        Text("\\(item)")
                    }
                }
            }
        }
        """

        let issues = analyzeSource(source)
        let forEachIssues = issues.filter {
            $0.message.contains("ForEach") && $0.message.contains("id")
        }

        let issue = try #require(forEachIssues.first)
        #expect(issue.ruleName == .forEachWithoutID)
    }

    @Test func testNoIssueForForEachWithID() {
        let source = """
        struct TestView: View {
            struct Item: Identifiable {
                let id: UUID
                let name: String
            }
            @State private var items: [Item] = []

            var body: some View {
                VStack {
                    ForEach(items, id: \\.id) { item in
                        Text(item.name)
                    }
                }
            }
        }
        """

        let issues = analyzeSource(source)
        let forEachWithoutIDIssues = issues.filter {
            $0.message.contains("ForEach missing explicit id")
        }

        #expect(forEachWithoutIDIssues.isEmpty)
    }

    // MARK: - ForEach Identifiable Suppression Tests

    @Test func testNoIssueForForEachWithIdentifiableAllCases() {
        let source = """
        struct TestView: View {
            var body: some View {
                ForEach(Severity.allCases) { severity in
                    Text(severity.displayName)
                }
            }
        }
        """

        let issues = analyzeSource(source, identifiableTypes: ["Severity"])
        let forEachIssues = issues.filter { $0.ruleName == .forEachWithoutID }
        #expect(forEachIssues.isEmpty)
    }

    @Test func testStillFlagsForEachWithNonIdentifiableAllCases() {
        let source = """
        struct TestView: View {
            var body: some View {
                ForEach(MyEnum.allCases) { item in
                    Text(item.name)
                }
            }
        }
        """

        // MyEnum is NOT in the Identifiable set
        let issues = analyzeSource(source, identifiableTypes: ["OtherType"])
        let forEachIssues = issues.filter { $0.ruleName == .forEachWithoutID }
        #expect(forEachIssues.count == 1)
    }

    @Test func testNoIssueForForEachWithIdentifiableTypedArray() {
        let source = """
        struct TestView: View {
            let items: [Item]

            var body: some View {
                ForEach(items) { item in
                    Text(item.name)
                }
            }
        }
        """

        let issues = analyzeSource(source, identifiableTypes: ["Item"])
        let forEachIssues = issues.filter { $0.ruleName == .forEachWithoutID }
        #expect(forEachIssues.isEmpty)
    }

    @Test func testNoIssueForForEachWithIdentifiableMemberProperty() {
        let source = """
        struct TestView: View {
            let viewModel: ViewModel

            var body: some View {
                ForEach(viewModel.backups) { backup in
                    Text(backup.name)
                }
            }
        }
        """

        // We can't resolve the type of viewModel.backups without type info,
        // so this should still flag (element type unknown)
        let issues = analyzeSource(source, identifiableTypes: ["ConfigBackup"])
        let forEachIssues = issues.filter { $0.ruleName == .forEachWithoutID }
        #expect(forEachIssues.count == 1)
    }
}

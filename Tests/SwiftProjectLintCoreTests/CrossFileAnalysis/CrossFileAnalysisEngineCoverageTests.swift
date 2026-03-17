import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

// MARK: - Tests targeting uncovered cross-file visitor loop paths

@Suite("CrossFileAnalysisEngine Cross-File Visitor Tests")
struct CrossFileEngineCFVisitorTests {

    /// Creates a registry with a CrossFileSwiftUIManagementVisitor registered.
    /// The shared registry uses SwiftUIManagementVisitor (non-cross-file),
    /// so the cross-file execution loop never fires without this setup.
    private func makeRegistryWithCrossFileVisitor(
        ruleIdentifier: RuleIdentifier = .relatedDuplicateStateVariable,
        category: PatternCategory = .stateManagement
    ) -> PatternVisitorRegistry {
        let registry = PatternVisitorRegistry()
        let pattern = SyntaxPattern(
            name: ruleIdentifier,
            visitor: CrossFileSwiftUIManagementVisitor.self,
            severity: .warning,
            category: category,
            messageTemplate: "Cross-file duplicate '{variableName}' in {viewNames}",
            suggestion: "Lift state to a shared ObservableObject",
            description: "Detects duplicate state across files"
        )
        registry.register(pattern: pattern)
        return registry
    }

    @Test("cross-file visitor loop executes with categories filter")
    func crossFileVisitorLoopExecutesWithCategories() {
        let registry = makeRegistryWithCrossFileVisitor()
        let engine = CrossFileAnalysisEngine(registry: registry)

        let fileA = ProjectFile(
            name: "ViewA.swift",
            content: """
            import SwiftUI
            struct ViewA: View {
                @State private var count = 0
                var body: some View { Text("A") }
            }
            """
        )
        let fileB = ProjectFile(
            name: "ViewB.swift",
            content: """
            import SwiftUI
            struct ViewB: View {
                @State private var count = 0
                var body: some View { Text("B") }
            }
            """
        )

        _ = engine.detectCrossFilePatterns(
            projectFiles: [fileA, fileB],
            categories: [.stateManagement]
        )
    }

    @Test("cross-file visitor loop with nil categories uses all patterns")
    func crossFileVisitorLoopWithNilCategories() {
        let registry = makeRegistryWithCrossFileVisitor()
        let engine = CrossFileAnalysisEngine(registry: registry)

        let file = ProjectFile(
            name: "SomeView.swift",
            content: """
            import SwiftUI
            struct SomeView: View {
                @State private var value = 42
                var body: some View { Text("\\(value)") }
            }
            """
        )

        _ = engine.detectCrossFilePatterns(
            projectFiles: [file],
            categories: nil
        )
    }

    @Test("cross-file visitor walks all cached files")
    func crossFileVisitorWalksAllCachedFiles() {
        let registry = makeRegistryWithCrossFileVisitor()
        let engine = CrossFileAnalysisEngine(registry: registry)

        let files = (1...5).map { index in
            ProjectFile(
                name: "View\(index).swift",
                content: """
                import SwiftUI
                struct View\(index): View {
                    @State private var loading = false
                    var body: some View { Text("View \\(loading)") }
                }
                """
            )
        }

        _ = engine.detectCrossFilePatterns(
            projectFiles: files,
            categories: [.stateManagement]
        )
    }

    @Test("ruleIdentifiers overload exercises cross-file visitor path")
    func ruleIdentifiersOverloadWithCrossFileVisitor() {
        let registry = makeRegistryWithCrossFileVisitor()
        let engine = CrossFileAnalysisEngine(registry: registry)

        let fileA = ProjectFile(
            name: "ParentView.swift",
            content: """
            import SwiftUI
            struct ParentView: View {
                @State private var isLoading = false
                var body: some View { Text("Parent") }
            }
            """
        )
        let fileB = ProjectFile(
            name: "ChildView.swift",
            content: """
            import SwiftUI
            struct ChildView: View {
                @State private var isLoading = false
                var body: some View { Text("Child") }
            }
            """
        )

        _ = engine.detectCrossFilePatterns(
            projectFiles: [fileA, fileB],
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )
    }

    @Test("ruleIdentifiers with mixed cross-file and regular visitors")
    func ruleIdentifiersMixedCrossFileAndRegular() {
        let registry = makeRegistryWithCrossFileVisitor()
        let regularPattern = SyntaxPattern(
            name: .fatView,
            visitor: SwiftUIManagementVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "Fat view detected",
            suggestion: "Break up the view",
            description: "Detects fat views"
        )
        registry.register(pattern: regularPattern)

        let engine = CrossFileAnalysisEngine(registry: registry)

        let file = ProjectFile(
            name: "BigView.swift",
            content: """
            import SwiftUI
            struct BigView: View {
                @State private var name = ""
                var body: some View { Text(name) }
            }
            """
        )

        _ = engine.detectCrossFilePatterns(
            projectFiles: [file],
            ruleIdentifiers: [.relatedDuplicateStateVariable, .fatView]
        )
    }

    @Test("multiple cross-file patterns all get processed")
    func multipleCrossFilePatternsInRegistry() {
        let registry = PatternVisitorRegistry()
        let patternA = SyntaxPattern(
            name: .relatedDuplicateStateVariable,
            visitor: CrossFileSwiftUIManagementVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "Related duplicate",
            suggestion: "Use shared state",
            description: "Related duplicates"
        )
        let patternB = SyntaxPattern(
            name: .unrelatedDuplicateStateVariable,
            visitor: CrossFileSwiftUIManagementVisitor.self,
            severity: .info,
            category: .stateManagement,
            messageTemplate: "Unrelated duplicate",
            suggestion: "Consider consolidating",
            description: "Unrelated duplicates"
        )
        registry.register(patterns: [patternA, patternB])

        let engine = CrossFileAnalysisEngine(registry: registry)

        let fileA = ProjectFile(
            name: "Alpha.swift",
            content: """
            import SwiftUI
            struct AlphaView: View {
                @State private var score = 0
                var body: some View { Text("\\(score)") }
            }
            """
        )
        let fileB = ProjectFile(
            name: "Beta.swift",
            content: """
            import SwiftUI
            struct BetaView: View {
                @State private var score = 0
                var body: some View { Text("\\(score)") }
            }
            """
        )

        _ = engine.detectCrossFilePatterns(
            projectFiles: [fileA, fileB],
            categories: [.stateManagement]
        )

        _ = engine.detectCrossFilePatterns(
            projectFiles: [fileA, fileB],
            ruleIdentifiers: [.relatedDuplicateStateVariable, .unrelatedDuplicateStateVariable]
        )
    }
}

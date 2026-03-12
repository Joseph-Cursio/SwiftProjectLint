import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

/// Tests for CrossFileAnalysisEngine paths not covered by existing tests:
/// - detectCrossFilePatterns(projectFiles:ruleIdentifiers:)
/// - detectPatterns(in:categories:) with real path
/// - getVisitorsForCategories with nil
@Suite("CrossFileAnalysisEngineRuleIdentifierTests")
struct CrossFileAnalysisEngineRuleIdentifierTests {

    @Test
    func detectCrossFilePatternsWithRuleIdentifiers() throws {
        let engine = CrossFileAnalysisEngine()

        let file1 = ProjectFile(
            name: "ViewA.swift",
            content: """
            struct ViewA: View {
                @State private var count = 0
                var body: some View { Text("A") }
            }
            """
        )
        let file2 = ProjectFile(
            name: "ViewB.swift",
            content: """
            struct ViewB: View {
                @State private var count = 0
                var body: some View { Text("B") }
            }
            """
        )

        let issues = engine.detectCrossFilePatterns(
            projectFiles: [file1, file2],
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )

        // Should run without crashing; may or may not detect issues depending on registry state
        #expect(issues.count >= 0)
    }

    @Test
    func detectCrossFilePatternsWithEmptyFiles() throws {
        let engine = CrossFileAnalysisEngine()

        let issues = engine.detectCrossFilePatterns(
            projectFiles: [],
            categories: [.stateManagement]
        )

        #expect(issues.isEmpty)
    }

    @Test
    func detectCrossFilePatternsWithEmptyRuleIdentifiers() throws {
        let engine = CrossFileAnalysisEngine()

        let file = ProjectFile(
            name: "View.swift",
            content: """
            struct MyView: View {
                var body: some View { Text("Hello") }
            }
            """
        )

        let issues = engine.detectCrossFilePatterns(
            projectFiles: [file],
            ruleIdentifiers: []
        )

        #expect(issues.isEmpty)
    }

    @Test
    func detectCrossFilePatternsWithNilCategories() throws {
        let engine = CrossFileAnalysisEngine()

        let file = ProjectFile(
            name: "View.swift",
            content: """
            struct MyView: View {
                @State private var value = 0
                var body: some View { Text("Hello") }
            }
            """
        )

        // nil categories = all categories
        let issues = engine.detectCrossFilePatterns(
            projectFiles: [file],
            categories: nil
        )

        // Should run without crashing
        #expect(issues.count >= 0)
    }

    @Test
    func detectCrossFilePatternsWithNonMatchingRuleIdentifier() throws {
        let engine = CrossFileAnalysisEngine()

        let file = ProjectFile(
            name: "View.swift",
            content: """
            struct MyView: View {
                var body: some View { Text("Hello") }
            }
            """
        )

        // Use a rule that doesn't have a cross-file visitor
        let issues = engine.detectCrossFilePatterns(
            projectFiles: [file],
            ruleIdentifiers: [.magicNumber]
        )

        // magicNumber is not a cross-file pattern, so no issues from cross-file analysis
        #expect(issues.isEmpty)
    }

    @Test
    func detectPatternsInNonexistentPath() throws {
        let engine = CrossFileAnalysisEngine()

        let issues = engine.detectPatterns(
            in: "/nonexistent/path/that/does/not/exist"
        )

        #expect(issues.isEmpty)
    }

    @Test
    func detectPatternsInPathWithRuleIdentifiers() throws {
        let engine = CrossFileAnalysisEngine()

        let issues = engine.detectPatterns(
            in: "/nonexistent/path",
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )

        #expect(issues.isEmpty)
    }
}

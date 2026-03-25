import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import Core

/// Tests for CrossFileAnalysisEngine paths not covered by existing tests:
/// - detectCrossFilePatterns(projectFiles:ruleIdentifiers:)
/// - detectPatterns(in:categories:) with real path
/// - getVisitorsForCategories with nil
@Suite("RuleIdentifierTests")
struct RuleIdentifierTests {

    // swiftprojectlint:disable Test Missing Require
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

    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func detectCrossFilePatternsWithEmptyFiles() throws {
        let engine = CrossFileAnalysisEngine()

        let issues = engine.detectCrossFilePatterns(
            projectFiles: [],
            categories: [.stateManagement]
        )

        #expect(issues.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    }

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
    @Test
    func detectPatternsInNonexistentPath() async throws {
        let engine = CrossFileAnalysisEngine()

        let issues = await engine.detectPatterns(
            in: "/nonexistent/path/that/does/not/exist"
        )

        #expect(issues.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func detectPatternsInPathWithRuleIdentifiers() async throws {
        let engine = CrossFileAnalysisEngine()

        let issues = await engine.detectPatterns(
            in: "/nonexistent/path",
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )

        #expect(issues.isEmpty)
    }
}

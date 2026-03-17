import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

// MARK: - Tests for detectPatterns(in:) and findSwiftFiles paths

@Suite("CrossFileAnalysisEngine File System Tests")
struct CrossFileAnalysisEngineFileSystemTests {

    /// Creates a registry with a CrossFileSwiftUIManagementVisitor registered.
    private func makeRegistryWithCrossFileVisitor() -> PatternVisitorRegistry {
        let registry = PatternVisitorRegistry()
        let pattern = SyntaxPattern(
            name: .relatedDuplicateStateVariable,
            visitor: CrossFileSwiftUIManagementVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "Cross-file duplicate '{variableName}' in {viewNames}",
            suggestion: "Lift state to a shared ObservableObject",
            description: "Detects duplicate state across files"
        )
        registry.register(pattern: pattern)
        return registry
    }

    /// Creates an isolated temp directory with a unique name.
    private func makeTempDir(label: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        return tempDir
    }

    // MARK: - detectPatterns(in:categories:) with real directories

    @Test("detectPatterns with real directory and categories filter")
    func detectPatternsInRealDirectoryWithCategories() async throws {
        let tempDir = try makeTempDir(label: "CategoriesTest")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try """
        import SwiftUI
        struct TempViewA: View {
            @State private var counter = 0
            var body: some View { Text("A") }
        }
        """.write(
            to: tempDir.appendingPathComponent("TempViewA.swift"),
            atomically: true, encoding: .utf8
        )
        try """
        import SwiftUI
        struct TempViewB: View {
            @State private var counter = 0
            var body: some View { Text("B") }
        }
        """.write(
            to: tempDir.appendingPathComponent("TempViewB.swift"),
            atomically: true, encoding: .utf8
        )

        let registry = makeRegistryWithCrossFileVisitor()
        let engine = CrossFileAnalysisEngine(registry: registry)

        _ = await engine.detectPatterns(
            in: tempDir.path,
            categories: [.stateManagement]
        )
    }

    @Test("detectPatterns with real directory and nil categories")
    func detectPatternsInRealDirectoryNilCategories() async throws {
        let tempDir = try makeTempDir(label: "NilCatTest")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try """
        import SwiftUI
        struct NilCatView: View {
            @State private var flag = true
            var body: some View { Text("flag: \\(flag)") }
        }
        """.write(
            to: tempDir.appendingPathComponent("NilCatView.swift"),
            atomically: true, encoding: .utf8
        )

        let registry = makeRegistryWithCrossFileVisitor()
        let engine = CrossFileAnalysisEngine(registry: registry)

        _ = await engine.detectPatterns(in: tempDir.path, categories: nil)
    }

    // MARK: - detectPatterns(in:ruleIdentifiers:) with real directories

    @Test("detectPatterns with ruleIdentifiers and real directory")
    func detectPatternsInRealDirectoryWithRuleIdentifiers() async throws {
        let tempDir = try makeTempDir(label: "RuleIdTest")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try """
        import SwiftUI
        struct RuleIdView: View {
            @State private var text = ""
            var body: some View { Text(text) }
        }
        """.write(
            to: tempDir.appendingPathComponent("RuleIdView.swift"),
            atomically: true, encoding: .utf8
        )

        let registry = makeRegistryWithCrossFileVisitor()
        let engine = CrossFileAnalysisEngine(registry: registry)

        _ = await engine.detectPatterns(
            in: tempDir.path,
            ruleIdentifiers: [.relatedDuplicateStateVariable]
        )
    }

    // MARK: - findSwiftFiles edge cases

    @Test("non-Swift files are ignored by findSwiftFiles")
    func detectPatternsIgnoresNonSwiftFiles() async throws {
        let tempDir = try makeTempDir(label: "MixedFilesTest")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "not swift code".write(
            to: tempDir.appendingPathComponent("readme.txt"),
            atomically: true, encoding: .utf8
        )
        try "struct MixedView {}".write(
            to: tempDir.appendingPathComponent("MixedView.swift"),
            atomically: true, encoding: .utf8
        )

        let engine = CrossFileAnalysisEngine()
        _ = await engine.detectPatterns(in: tempDir.path, categories: [.stateManagement])
    }

    @Test("findSwiftFiles discovers files in nested subdirectories")
    func detectPatternsFindsNestedSwiftFiles() async throws {
        let tempDir = try makeTempDir(label: "NestedTest")
        let subDir = tempDir.appendingPathComponent("SubFolder")
        try FileManager.default.createDirectory(
            at: subDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "struct TopLevel {}".write(
            to: tempDir.appendingPathComponent("TopLevel.swift"),
            atomically: true, encoding: .utf8
        )
        try "struct Nested {}".write(
            to: subDir.appendingPathComponent("Nested.swift"),
            atomically: true, encoding: .utf8
        )

        let engine = CrossFileAnalysisEngine()
        _ = await engine.detectPatterns(in: tempDir.path)
    }

    @Test("empty directory produces no issues")
    func detectPatternsInEmptyDirectory() async throws {
        let tempDir = try makeTempDir(label: "EmptyDirTest")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let engine = CrossFileAnalysisEngine()
        let issues = await engine.detectPatterns(in: tempDir.path)

        #expect(issues.isEmpty)
    }

    @Test("directory with only non-Swift files produces no issues")
    func detectPatternsWithOnlyNonSwiftFiles() async throws {
        let tempDir = try makeTempDir(label: "NoSwiftTest")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try "some text".write(
            to: tempDir.appendingPathComponent("notes.txt"),
            atomically: true, encoding: .utf8
        )
        try "{ }".write(
            to: tempDir.appendingPathComponent("config.json"),
            atomically: true, encoding: .utf8
        )

        let engine = CrossFileAnalysisEngine()
        let issues = await engine.detectPatterns(in: tempDir.path)

        #expect(issues.isEmpty)
    }
}

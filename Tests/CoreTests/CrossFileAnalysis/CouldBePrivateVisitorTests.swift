import Testing
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct CouldBePrivateVisitorTests {

    private func analyze(files: [String: SourceFileSyntax]) -> [LintIssue] {
        let pattern = CouldBePrivate().pattern
        let visitor = CouldBePrivateVisitor(fileCache: files)
        visitor.setPattern(pattern)
        for (name, ast) in files {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(
                SourceLocationConverter(fileName: name, tree: ast)
            )
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .couldBePrivate }
    }

    @Test func detectsTypeOnlyUsedInDeclaringFile() {
        let fileA = Parser.parse(source: """
        struct HelperView: View {
            var body: some View { Text("hi") }
        }

        struct MainView: View {
            var body: some View { HelperView() }
        }
        """)

        let fileB = Parser.parse(source: """
        struct OtherView: View {
            var body: some View { Text("other") }
        }
        """)

        let cache = ["FileA.swift": fileA, "FileB.swift": fileB]
        let pattern = CouldBePrivate().pattern
        let visitor = CouldBePrivateVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        // Walk each file with its name set
        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()

        let issues = visitor.detectedIssues.filter { $0.ruleName == .couldBePrivate }
        let flaggedNames = issues.map { $0.message }

        // HelperView is only used in FileA — should be flagged
        #expect(flaggedNames.contains { $0.contains("HelperView") })
        // MainView is only used in FileA — should also be flagged
        #expect(flaggedNames.contains { $0.contains("MainView") })
        // OtherView is only used in FileB — should be flagged
        #expect(flaggedNames.contains { $0.contains("OtherView") })
    }

    @Test func doesNotFlagTypeUsedAcrossFiles() {
        let fileA = Parser.parse(source: """
        struct SharedModel {
            let name: String
        }
        """)

        let fileB = Parser.parse(source: """
        struct Consumer: View {
            let model: SharedModel
            var body: some View { Text(model.name) }
        }
        """)

        let cache = ["FileA.swift": fileA, "FileB.swift": fileB]
        let pattern = CouldBePrivate().pattern
        let visitor = CouldBePrivateVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()

        let flaggedNames = visitor.detectedIssues
            .filter { $0.ruleName == .couldBePrivate }
            .map { $0.message }

        // SharedModel is referenced in FileB — should NOT be flagged
        #expect(flaggedNames.contains { $0.contains("SharedModel") } == false)

    }

    // MARK: - Class, Enum, Actor Declarations

    @Test func flagsClassOnlyUsedInDeclaringFile() {
        let fileA = Parser.parse(source: """
        class InternalService {
            func run() { }
        }
        """)
        let fileB = Parser.parse(source: """
        struct Other { }
        """)

        let issues = analyze(files: ["FileA.swift": fileA, "FileB.swift": fileB])
        let flagged = issues.map(\.message)
        #expect(flagged.contains { $0.contains("InternalService") })
    }

    @Test func flagsEnumOnlyUsedInDeclaringFile() {
        let fileA = Parser.parse(source: """
        enum Direction { case north, south }
        """)
        let fileB = Parser.parse(source: """
        struct Other { }
        """)

        let issues = analyze(files: ["FileA.swift": fileA, "FileB.swift": fileB])
        let flagged = issues.map(\.message)
        #expect(flagged.contains { $0.contains("Direction") })
    }

    @Test func flagsActorOnlyUsedInDeclaringFile() {
        let fileA = Parser.parse(source: """
        actor DataStore {
            func save() { }
        }
        """)
        let fileB = Parser.parse(source: """
        struct Other { }
        """)

        let issues = analyze(files: ["FileA.swift": fileA, "FileB.swift": fileB])
        let flagged = issues.map(\.message)
        #expect(flagged.contains { $0.contains("DataStore") })
    }

    // MARK: - Test File Skipping

    @Test func skipsTypesInTestFiles() {
        let testFile = Parser.parse(source: """
        struct TestHelper {
            func setup() { }
        }
        """)
        let other = Parser.parse(source: """
        struct Other { }
        """)

        let issues = analyze(
            files: ["Tests/MyTests/TestHelper.swift": testFile, "Other.swift": other]
        )
        let flagged = issues.map(\.message)
        #expect(flagged.contains { $0.contains("TestHelper") } == false)
    }

    // MARK: - Existing tests

    @Test func skipsPrivateAndPublicTypes() {
        let file = Parser.parse(source: """
        private struct AlreadyPrivate {
            let value: Int
        }
        public struct AlreadyPublic {
            let value: Int
        }
        struct InternalType {
            let value: Int
        }
        """)

        let cache = ["File.swift": file]
        let pattern = CouldBePrivate().pattern
        let visitor = CouldBePrivateVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()

        let flaggedNames = visitor.detectedIssues
            .filter { $0.ruleName == .couldBePrivate }
            .map { $0.message }

        #expect(flaggedNames.contains { $0.contains("AlreadyPrivate") } == false)

        #expect(flaggedNames.contains { $0.contains("AlreadyPublic") } == false)

        // InternalType (default access, only in one file) should be flagged
        #expect(flaggedNames.contains { $0.contains("InternalType") })
    }
}

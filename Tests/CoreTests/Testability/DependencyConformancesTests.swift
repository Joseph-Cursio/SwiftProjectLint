@testable import Core
import Foundation
@testable import SwiftProjectLintEngine
import SwiftProjectLintModels
import Testing

/// **A dependency type the project stores is vouched for when its resolved checkout declares it
/// `Equatable`** — and only then.
///
/// SwiftLintRuleStudio's `YAMLConfig` stores `[String: Node]`, and Yams declares
/// `public enum Node: Hashable`. With nothing read from `.build/checkouts`, `Node` blocked every
/// remedy through `YAMLConfig`, so `MigrationAssistant.applyMigration(_:to: inout YAMLConfig)` — a
/// pure mutator two keywords from a law — was never seeded. The first attempt read every file in
/// the checkouts and still vouched for nothing: swift-syntax's `CodeGeneration` package declares a
/// `class Node`, a namesake. Reading only the modules the project imports is what fixed it.
@Suite("Dependency conformances — Equatable read from resolved checkouts")
struct DependencyConformancesTests {

    // MARK: - Reading headers

    @Test("a primary declaration's conformances are read, modifiers and attributes allowed")
    func primaryDeclaration() {
        let found = DependencyConformances.declarations(in: """
        @frozen public indirect enum Node: Hashable, Sendable {
            case scalar(String)
        }
        """)
        let expected = DependencyConformances.Declaration(
            kind: .primary, name: "Node", isGeneric: false, conformances: ["Hashable", "Sendable"]
        )
        #expect(found == [expected])
    }

    @Test("an extension's conformances count, a conditional one does not, and a comment is not code")
    func extensionsAndComments() {
        let found = DependencyConformances.declarations(in: """
        public struct Scalar { let s: String }
        extension Node.Scalar: Swift.Equatable {}
        extension Box: Equatable where T: Equatable {}
        // extension Fake: Equatable {}
        /* struct Hidden: Equatable { } */
        """)
        #expect(found.map(\.name) == ["Scalar", "Scalar", "Box"])
        #expect(found[1].kind == .unconditionalExtension)
        #expect(found[1].conformances == ["Equatable"])
        #expect(found[2].kind == .conditionalExtension)
    }

    // MARK: - The vouching rule

    private func vouched(_ text: String) -> Set<String> {
        DependencyConformances.vouched(DependencyConformances.declarations(in: text))
    }

    @Test("declared Equatable, Hashable or Comparable is vouched for, inline or by extension")
    func vouchedConformances() {
        #expect(vouched("public enum Node: Hashable {}") == ["Node"])
        #expect(vouched("public struct Mark {}\nextension Mark: Comparable {}") == ["Mark"])
    }

    @Test("not vouched: no conformance, a conditional one, a generic type, or a namesake", arguments: [
        "public struct Node {}",
        "public struct Node {}\nextension Node: Equatable where Self: Sendable {}",
        "public struct Node<T>: Equatable {}",
        "public enum Node: Hashable {}\npublic final class Node {}"
    ])
    func notVouched(text: String) {
        #expect(vouched(text).isEmpty)
    }

    @Test("imports are read in every spelling")
    func imports() {
        let modules = DependencyConformances.importedModules(in: [
            "import Yams\n@testable import Core\nimport struct Foundation.Date\npublic import Kit\n// import Fake"
        ])
        #expect(modules == ["Yams", "Core", "Foundation", "Kit"])
    }

    // MARK: - Through a run

    /// A project storing a dependency's `Node`, with a namesake in a module it does not import —
    /// the swift-syntax `CodeGeneration` shape.
    private static let files: [String: String] = [
        "Sources/App/Config.swift": """
        import Yams

        public struct YAMLConfig {
            public var keys: [String] = []
            var passthrough: [String: Node] = [:]
        }

        public enum Migrations {
            public static func add(_ key: String, to config: inout YAMLConfig) {
                if !config.keys.contains(key) { config.keys.append(key) }
            }
        }
        """,
        ".build/checkouts/Yams/Sources/Yams/Node.swift": "public enum Node: Hashable { case scalar(String) }",
        ".build/checkouts/Other/Sources/CodeGeneration/Node.swift": "public class Node {}"
    ]

    private func analyse(_ files: [String: String]) async throws -> [LintIssue] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DependencyConformances-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return await ProjectLinter().analyzeProject(
            at: root.path,
            ruleIdentifiers: [.missingEquatableOnPureResult, .pureMutatorCandidate],
            detector: PatternRegistryFactory.createConfiguredSystem().detector
        )
    }

    @Test("a mutator over a type storing a dependency's Equatable type is a near miss naming only the project type")
    func vouchedThroughARun() async throws {
        let issues = try await analyse(Self.files)
        let finding = try #require(issues.first { $0.symbol == "add" })
        #expect(finding.ruleName == .missingEquatableOnPureResult)
        #expect(finding.mutates == "config")
        #expect(finding.requires == PBTSeedRequirement(equatable: ["YAMLConfig"]))
    }

    @Test("without the checkout, the same type stays blocked")
    func unresolvedDependencyBlocks() async throws {
        var files = Self.files
        files[".build/checkouts/Yams/Sources/Yams/Node.swift"] = nil
        let issues = try await analyse(files)
        #expect(issues.contains { $0.symbol == "add" } == false)
    }

    @Test("a namesake in an imported module blocks")
    func importedNamesakeBlocks() async throws {
        var files = Self.files
        files[".build/checkouts/Other/Sources/Yams/Other.swift"] = "public final class Node {}"
        let issues = try await analyse(files)
        #expect(issues.contains { $0.symbol == "add" } == false)
    }
}

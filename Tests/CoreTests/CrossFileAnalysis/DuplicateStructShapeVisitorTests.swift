@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct DuplicateStructShapeVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = DuplicateStructShape().pattern
        let visitor = DuplicateStructShapeVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .duplicateStructShape }
    }

    /// Five structs share a four-property core (rawKey/name/description/category) with no
    /// shared protocol — one issue per struct, each naming the four shared properties.
    @Test
    func sharedCoreWithoutProtocolFlagsEveryMember() throws {
        let issues = analyze(files: [
            "Models.swift": """
            struct CompilerFlag {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
                let source: String
            }
            struct EffectiveSetting {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
                let value: String
            }
            struct SettingOverride {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
                let origin: String
            }
            struct DeprecatedSetting {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
                let currentValue: String
            }
            struct SettingDiff {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
                let diffType: String
            }
            """
        ])

        #expect(issues.count == 5)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("rawKey"))
        #expect(issue.message.contains("category"))
    }

    /// The cluster spans two files — confirms the cross-file accumulation works and that
    /// each issue is reported at the participating type's own file.
    @Test
    func clusterSpansFiles() {
        let issues = analyze(files: [
            "A.swift": """
            struct Alpha {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
            }
            struct Beta {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
            }
            """,
            "B.swift": """
            struct Gamma {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
            }
            """
        ])

        #expect(issues.count == 3)
        #expect(Set(issues.map(\.filePath)) == ["A.swift", "B.swift"])
    }

    /// Only two properties in common — below the four-property threshold. No issue.
    @Test
    func belowThresholdIsClean() {
        let issues = analyze(files: [
            "Models.swift": """
            struct User {
                let id: String
                let name: String
                let email: String
            }
            struct Product {
                let id: String
                let name: String
                let price: Double
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// Both types already conform to a protocol that covers the shared core — the
    /// abstraction exists, so neither is reported.
    @Test
    func coveredBySharedProtocolIsClean() {
        let issues = analyze(files: [
            "Models.swift": """
            protocol Identity {
                var rawKey: String { get }
                var name: String { get }
                var description: String? { get }
                var category: String { get }
            }
            struct AlphaSetting: Identity {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
                let alpha: Int
            }
            struct BetaSetting: Identity {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
                let beta: Int
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// A type already abstracted (conforms to a covering protocol) is dropped from a cluster
    /// while its un-abstracted peers are still reported.
    @Test
    func abstractedMemberIsSuppressedWithinMixedCluster() {
        let issues = analyze(files: [
            "Models.swift": """
            protocol Identity {
                var rawKey: String { get }
                var name: String { get }
                var description: String? { get }
                var category: String { get }
            }
            struct Abstracted: Identity {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
            }
            struct Raw1 {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
            }
            struct Raw2 {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
            }
            """
        ])

        #expect(issues.count == 2)
        #expect(issues.contains { $0.message.contains("'Abstracted'") } == false)
    }

    /// Computed properties do not contribute to the fingerprint, so two types whose only
    /// overlap is computed vars are not clustered.
    @Test
    func computedPropertiesAreIgnored() {
        let issues = analyze(files: [
            "Models.swift": """
            struct ViewA {
                var rawKey: String { "a" }
                var name: String { "a" }
                var description: String? { nil }
                var category: String { "a" }
                let stored: Int
            }
            struct ViewB {
                var rawKey: String { "b" }
                var name: String { "b" }
                var description: String? { nil }
                var category: String { "b" }
                let stored: Int
            }
            """
        ])

        #expect(issues.isEmpty)
    }
}

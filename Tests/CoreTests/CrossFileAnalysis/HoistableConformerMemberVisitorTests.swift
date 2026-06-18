@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct HoistableConformerMemberVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = HoistableConformerMember().pattern
        let visitor = HoistableConformerMemberVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .hoistableConformerMember }
    }

    private static let namedProtocol = """
    protocol Named {
        var rawKey: String { get }
        var name: String { get }
    }
    """

    /// Three types conforming to `Named` each implement `matches` identically, using only
    /// `Named`'s requirements — the canonical hoist case. One issue per participating type.
    @Test
    func identicalMethodOverConformersHoists() throws {
        let issues = analyze(files: [
            "P.swift": Self.namedProtocol,
            "A.swift": """
            struct Alpha: Named {
                let rawKey: String
                let name: String
                func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
            }
            """,
            "B.swift": """
            struct Beta: Named {
                let rawKey: String
                let name: String
                func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
            }
            """,
            "C.swift": """
            struct Gamma: Named {
                let rawKey: String
                let name: String
                func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
            }
            """
        ])

        #expect(issues.count == 3)
        #expect(issues.allSatisfy { $0.message.contains("matches") })
        #expect(issues.allSatisfy { $0.message.contains("Named") })
        #expect(issues.contains { $0.message.contains("Beta") })
    }

    /// The compile guard: the shared body references `tag`, a stored field not declared by
    /// `Named`. Hoisting to `extension Named` would not compile, so the rule stays silent.
    @Test
    func bodyReferencingNonProtocolMemberNotHoisted() {
        let issues = analyze(files: [
            "P.swift": Self.namedProtocol,
            "A.swift": """
            struct Alpha: Named {
                let rawKey: String
                let name: String
                let tag: String
                func matches(_ query: String) -> Bool { rawKey.contains(query) || tag.contains(query) }
            }
            """,
            "B.swift": """
            struct Beta: Named {
                let rawKey: String
                let name: String
                let tag: String
                func matches(_ query: String) -> Bool { rawKey.contains(query) || tag.contains(query) }
            }
            """,
            "C.swift": """
            struct Gamma: Named {
                let rawKey: String
                let name: String
                let tag: String
                func matches(_ query: String) -> Bool { rawKey.contains(query) || tag.contains(query) }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// Two conformers is below the cluster threshold.
    @Test
    func twoConformersBelowThresholdClean() {
        let issues = analyze(files: [
            "P.swift": Self.namedProtocol,
            "A.swift": """
            struct Alpha: Named {
                let rawKey: String
                let name: String
                func label() -> String { rawKey + name }
            }
            """,
            "B.swift": """
            struct Beta: Named {
                let rawKey: String
                let name: String
                func label() -> String { rawKey + name }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// Already hoisted: an `extension Named` already provides `matches`. Three identical
    /// per-type overrides are a different smell (redundant overrides), so the rule must not
    /// suggest hoisting something already in the protocol extension.
    @Test
    func alreadyProvidedByProtocolExtensionClean() {
        let issues = analyze(files: [
            "P.swift": Self.namedProtocol + """

            extension Named {
                func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
            }
            """,
            "A.swift": """
            struct Alpha: Named {
                let rawKey: String
                let name: String
                func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
            }
            """,
            "B.swift": """
            struct Beta: Named {
                let rawKey: String
                let name: String
                func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
            }
            """,
            "C.swift": """
            struct Gamma: Named {
                let rawKey: String
                let name: String
                func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// No protocol unites the three types, so there is nowhere to hoist to.
    @Test
    func noCommonProtocolClean() {
        let issues = analyze(files: [
            "A.swift": """
            struct Alpha {
                let rawKey: String
                func describe() -> String { rawKey + "!" }
            }
            """,
            "B.swift": """
            struct Beta {
                let rawKey: String
                func describe() -> String { rawKey + "!" }
            }
            """,
            "C.swift": """
            struct Gamma {
                let rawKey: String
                func describe() -> String { rawKey + "!" }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// Same member name, different bodies — not a single shared implementation.
    @Test
    func differentBodiesClean() {
        let issues = analyze(files: [
            "P.swift": Self.namedProtocol,
            "A.swift": """
            struct Alpha: Named {
                let rawKey: String
                let name: String
                func label() -> String { rawKey }
            }
            """,
            "B.swift": """
            struct Beta: Named {
                let rawKey: String
                let name: String
                func label() -> String { name }
            }
            """,
            "C.swift": """
            struct Gamma: Named {
                let rawKey: String
                let name: String
                func label() -> String { rawKey + name }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// Computed properties hoist too, not just methods.
    @Test
    func identicalComputedPropertyHoists() {
        let issues = analyze(files: [
            "P.swift": Self.namedProtocol,
            "A.swift": """
            struct Alpha: Named {
                let rawKey: String
                let name: String
                var summary: String { rawKey + ": " + name }
            }
            """,
            "B.swift": """
            struct Beta: Named {
                let rawKey: String
                let name: String
                var summary: String { rawKey + ": " + name }
            }
            """,
            "C.swift": """
            struct Gamma: Named {
                let rawKey: String
                let name: String
                var summary: String { rawKey + ": " + name }
            }
            """
        ])

        #expect(issues.count == 3)
        #expect(issues.allSatisfy { $0.message.contains("summary") })
    }
}

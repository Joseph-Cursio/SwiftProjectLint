@testable import Core
@testable import SwiftProjectLintRules
import Testing

/// Conformances and uses written through a composition `typealias` are credited to every
/// protocol the alias composes. The alias's own definition is neither.
@Suite
struct UnusedProtocolAbstractionAliasTests {

    private func analyze(_ files: [String: String]) -> [LintIssue] {
        CrossFileVisitorTestSupport.issues(
            of: UnusedProtocolAbstractionVisitor.self,
            pattern: UnusedProtocolAbstraction().pattern,
            files: files
        )
    }

    private let roles = """
    protocol Reading { func read() }
    protocol Writing { func write() }
    typealias Storage = Reading & Writing
    """

    @Test
    func usingTheAliasAsATypeUsesEveryRole() {
        let issues = analyze([
            "Roles.swift": roles,
            "Disk.swift": "struct DiskStorage: Storage {}",
            "Client.swift": "final class Client { let storage: any Storage }"
        ])
        #expect(issues.isEmpty)
    }

    @Test(arguments: [
        "func copy<S: Storage>(_ storage: S) {}",
        "func copy(_ storage: some Storage) {}",
        "func make() -> any Storage { DiskStorage() }",
        "protocol CachedStorage: Storage {}",
        "let all: [any Storage] = []"
    ])
    func everyUsePositionCountsThroughTheAlias(use: String) {
        let issues = analyze([
            "Roles.swift": roles,
            "Disk.swift": "struct DiskStorage: Storage {}",
            "Use.swift": use
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func conformingThroughTheAliasIsAConformanceToEachRoleNotAUse() {
        let messages = analyze([
            "Roles.swift": roles,
            "Disk.swift": "struct DiskStorage: Storage {}"
        ]).map(\.message).sorted()

        #expect(messages.count == 2)
        #expect(messages.first?.contains("'Reading' is conformed to by 1 type") == true)
        #expect(messages.last?.contains("'Writing' is conformed to by 1 type") == true)
    }

    @Test
    func declaringTheAliasIsNotAUseOfItsComponents() {
        // Checkout's split store spells the conformance out, and declares the composition beside
        // it. The definition used to count as a use of every role, so a role nothing consumed
        // passed as used for as long as the alias existed.
        let issues = analyze([
            "Roles.swift": roles,
            "Disk.swift": "struct DiskStorage: Reading, Writing {}",
            "Client.swift": "final class Client { let reader: any Reading }"
        ])
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'Writing'") == true)
    }

    @Test
    func anAliasNestedInAnAliasIsFollowedThrough() {
        let issues = analyze([
            "Roles.swift": """
            protocol Reading { func read() }
            protocol Writing { func write() }
            typealias ReadOnly = Reading & Sendable
            typealias Storage = ReadOnly & Writing
            """,
            "Disk.swift": "struct DiskStorage: Storage {}",
            "Client.swift": "func store(_ storage: any Storage) {}"
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func anAmbiguousAliasKeepsItsDefinitionAsAUse() {
        // Two different `Element`s: neither is expanded, so neither definition is skipped, and
        // the rule behaves exactly as it did before aliases were followed.
        let issues = analyze([
            "A.swift": """
            protocol Reading { func read() }
            struct DiskStorage: Reading {}
            struct A { typealias Element = Reading }
            """,
            "B.swift": "struct B { typealias Element = Int }"
        ])
        #expect(issues.isEmpty)
    }
}

@testable import Core
import Foundation
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import Testing

/// Every cross-file rule that reads an inheritance clause by name sees a conformance written
/// through a composition `typealias` exactly as it sees the same conformance written out.
///
/// Each fixture is run three ways: spelled out, through the alias, and through the alias with
/// expansion switched off. The first two must agree. The third must not, which is what shows
/// the fixture reaches the conformance the rule reads; a fixture that agreed either way would
/// pass without testing anything.
///
/// `Single Implementation Protocol` and `Unused Protocol Abstraction` have suites of their own,
/// because what they count is the finding itself rather than a gate in front of it.
@Suite
struct CompositionAliasConformanceTests {

    @Test(arguments: AliasFixture.all)
    func throughTheAliasMatchesSpelledOut(_ fixture: AliasFixture) {
        let spelledOut = fixture.messages(conformance: fixture.spelledOut)
        let throughAlias = fixture.messages(conformance: fixture.alias)
        let unexpanded = fixture.messages(conformance: fixture.alias, followingAliases: false)

        #expect(spelledOut.count == fixture.expectedFindings)
        #expect(throughAlias == spelledOut)
        #expect(unexpanded != spelledOut)
    }
}

/// One rule's fixture. `{conformance}` in a file is replaced by the alias or by its spelling.
struct AliasFixture: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let files: [String: String]
    let alias: String
    let spelledOut: String
    let expectedFindings: Int
    let analyze: @Sendable (_ files: [String: String], _ followingAliases: Bool) -> [LintIssue]

    func messages(conformance: String, followingAliases: Bool = true) -> [String] {
        let substituted = files.mapValues {
            $0.replacingOccurrences(of: "{conformance}", with: conformance)
        }
        return analyze(substituted, followingAliases).map(\.message).sorted()
    }

    static let all: [Self] = [
        mirrorProtocol, couldAdoptProtocol, parallelEnumShapeSharedProtocol,
        parallelEnumShapeUbiquitousOnly, duplicateStructShape, sharedDomainEnumField,
        hoistableConformerMember
    ]

    /// A mirror reached only through the alias was missed: the conformer did not conform.
    static let mirrorProtocol = Self(
        testDescription: "Mirror Protocol",
        files: [
            "Service.swift": """
            protocol OrderServiceProtocol {
                func save()
                func load()
            }
            protocol Auditing { func audit() }
            typealias AuditedOrderService = OrderServiceProtocol & Auditing
            """,
            "OrderService.swift": """
            struct OrderService: {conformance} {
                func save() {}
                func load() {}
                func audit() {}
            }
            """
        ],
        alias: "AuditedOrderService",
        spelledOut: "OrderServiceProtocol, Auditing",
        expectedFindings: 1
    ) { files, follow in
        CrossFileVisitorTestSupport.issues(
            of: MirrorProtocolVisitor.self, pattern: MirrorProtocol().pattern,
            files: files, followingAliases: follow
        )
    }

    /// A type conforming through the alias was told to adopt a protocol it already adopts.
    static let couldAdoptProtocol = Self(
        testDescription: "Could Adopt Protocol",
        files: [
            "Roles.swift": """
            protocol Located {
                var latitude: Double { get }
                var longitude: Double { get }
                var altitude: Double { get }
            }
            protocol Named { var name: String { get } }
            typealias Place = Located & Named
            """,
            "Landmark.swift": """
            struct Landmark: {conformance} {
                let latitude: Double
                let longitude: Double
                let altitude: Double
                let name: String
            }
            """
        ],
        alias: "Place",
        spelledOut: "Located, Named",
        expectedFindings: 0
    ) { files, follow in
        CrossFileVisitorTestSupport.issues(
            of: CouldAdoptProtocolVisitor.self, pattern: CouldAdoptProtocol().pattern,
            files: files, followingAliases: follow
        )
    }

    /// One enum adopts the shared domain protocol through an alias: they are already unified.
    static let parallelEnumShapeSharedProtocol = Self(
        testDescription: "Parallel Enum Shape — shared protocol through the alias",
        files: [
            "Ranked.swift": """
            protocol Ranked {}
            typealias RankedLevel = Ranked & CaseIterable
            """,
            "Severity.swift": "enum Severity: {conformance} { case low, medium, high }",
            "Priority.swift": "enum Priority: Ranked, CaseIterable { case low, medium, high }"
        ],
        alias: "RankedLevel",
        spelledOut: "Ranked, CaseIterable",
        expectedFindings: 0
    ) { files, follow in
        CrossFileVisitorTestSupport.issues(
            of: ParallelEnumShapeVisitor.self, pattern: ParallelEnumShape().pattern,
            files: files, followingAliases: follow
        )
    }

    /// An alias of ubiquitous protocols only is not a domain abstraction, so it unifies nothing.
    /// Read by its own name, it looked like one and silenced the rule.
    static let parallelEnumShapeUbiquitousOnly = Self(
        testDescription: "Parallel Enum Shape — an alias of ubiquitous protocols",
        files: [
            "Listable.swift": "typealias Listable = CaseIterable & Codable",
            "Severity.swift": "enum Severity: String, {conformance} { case low, medium, high }",
            "Priority.swift": "enum Priority: String, {conformance} { case low, medium, high }"
        ],
        alias: "Listable",
        spelledOut: "CaseIterable, Codable",
        expectedFindings: 2
    ) { files, follow in
        CrossFileVisitorTestSupport.issues(
            of: ParallelEnumShapeVisitor.self, pattern: ParallelEnumShape().pattern,
            files: files, followingAliases: follow
        )
    }

    /// The shared core is covered by a protocol both types adopt through the alias.
    static let duplicateStructShape = Self(
        testDescription: "Duplicate Struct Shape",
        files: [
            "Identity.swift": """
            protocol Identity {
                var rawKey: String { get }
                var name: String { get }
                var description: String? { get }
                var category: String { get }
            }
            typealias Setting = Identity & Sendable
            """,
            "Alpha.swift": """
            struct AlphaSetting: {conformance} {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
                let alpha: Int
            }
            """,
            "Beta.swift": """
            struct BetaSetting: {conformance} {
                let rawKey: String
                let name: String
                let description: String?
                let category: String
                let beta: Int
            }
            """
        ],
        alias: "Setting",
        spelledOut: "Identity, Sendable",
        expectedFindings: 0
    ) { files, follow in
        CrossFileVisitorTestSupport.issues(
            of: DuplicateStructShapeVisitor.self, pattern: DuplicateStructShape().pattern,
            files: files, followingAliases: follow
        )
    }

    /// The shared enum field is already a requirement of a protocol adopted through the alias.
    static let sharedDomainEnumField = Self(
        testDescription: "Shared Domain Enum Field",
        files: [
            "Severity.swift": """
            enum IssueSeverity { case error, warning }
            protocol Ranked { var severity: IssueSeverity { get } }
            typealias RankedItem = Ranked & Sendable
            """,
            "Alpha.swift": "struct Alpha: {conformance} { let severity: IssueSeverity }",
            "Beta.swift": "struct Beta: {conformance} { let severity: IssueSeverity }",
            "Gamma.swift": "struct Gamma: {conformance} { let severity: IssueSeverity }"
        ],
        alias: "RankedItem",
        spelledOut: "Ranked, Sendable",
        expectedFindings: 0
    ) { files, follow in
        CrossFileVisitorTestSupport.issues(
            of: SharedDomainEnumFieldVisitor.self, pattern: SharedDomainEnumField().pattern,
            files: files, followingAliases: follow
        )
    }

    /// Three conformers share a body over the protocol's requirements; the protocol they adopt
    /// through the alias is where it can be hoisted to.
    static let hoistableConformerMember = Self(
        testDescription: "Hoistable Conformer Member",
        files: [
            "Named.swift": """
            protocol Named {
                var rawKey: String { get }
                var name: String { get }
            }
            typealias NamedItem = Named & Sendable
            """,
            "Alpha.swift": hoistableConformer("Alpha"),
            "Beta.swift": hoistableConformer("Beta"),
            "Gamma.swift": hoistableConformer("Gamma")
        ],
        alias: "NamedItem",
        spelledOut: "Named, Sendable",
        expectedFindings: 3
    ) { files, follow in
        CrossFileVisitorTestSupport.issues(
            of: HoistableConformerMemberVisitor.self, pattern: HoistableConformerMember().pattern,
            files: files, followingAliases: follow
        )
    }

    private static func hoistableConformer(_ name: String) -> String {
        """
        struct \(name): {conformance} {
            let rawKey: String
            let name: String
            func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
        }
        """
    }
}

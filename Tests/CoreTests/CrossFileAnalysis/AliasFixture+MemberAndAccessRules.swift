@testable import Core
@testable import SwiftProjectLintRules

extension AliasFixture {
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
            "Gamma.swift": "struct Gamma: {conformance} { let severity: IssueSeverity }",
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
            "Gamma.swift": hoistableConformer("Gamma"),
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

    /// A type conforming to a project protocol through the alias is used polymorphically.
    static let couldBePrivate = Self(
        testDescription: "Could Be Private",
        files: [
            "Rendering.swift": """
            protocol Rendering {}
            typealias Widget = Rendering & Sendable
            """,
            "Banner.swift": """
            struct Banner: {conformance} {}
            func showBanner() { _ = Banner() }
            """,
        ],
        alias: "Widget",
        spelledOut: "Rendering, Sendable",
        expectedFindings: 0
    ) { files, follow in
        CrossFileVisitorTestSupport.issues(
            of: CouldBePrivateVisitor.self, pattern: CouldBePrivate().pattern,
            files: files, followingAliases: follow
        )
    }

    /// `save()` witnesses a requirement adopted through the alias. Making it private would not
    /// compile.
    static let couldBePrivateMember = Self(
        testDescription: "Could Be Private Member",
        files: [
            "Saving.swift": """
            protocol Saving { func save() }
            typealias Store = Saving & Sendable
            """,
            "DiskStore.swift": "struct DiskStore: {conformance} { func save() {} }",
        ],
        alias: "Store",
        spelledOut: "Saving, Sendable",
        expectedFindings: 0
    ) { files, follow in
        CrossFileVisitorTestSupport.issues(
            of: CouldBePrivateMemberVisitor.self, pattern: CouldBePrivateMember().pattern,
            files: files, followingAliases: follow
        )
    }

    /// A view conforming through the alias conforms to `View`, so its members run on the main
    /// actor and a synchronous file read in one blocks it.
    static let blockingIOOnMainActor = Self(
        testDescription: "Blocking IO On Main Actor",
        files: [
            "Sources/App/TestableView.swift": """
            import SwiftUI
            protocol ViewInspectorHook {}
            typealias TestableView = View & ViewInspectorHook
            """,
            "Sources/App/ContentView.swift": """
            import SwiftUI
            struct ContentView: {conformance} {
                func load(from path: String) -> String {
                    (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                }
                var body: some View { Text("") }
            }
            """,
        ],
        alias: "TestableView",
        spelledOut: "View, ViewInspectorHook",
        expectedFindings: 1
    ) { files, follow in
        CrossFileVisitorTestSupport.issues(
            of: BlockingIOOnMainActorVisitor.self, pattern: BlockingIOOnMainActor().pattern,
            files: files, followingAliases: follow
        )
    }

    /// The roles are named outside their file only through the alias, which still names them.
    static let protocolCouldBePrivate = Self(
        testDescription: "Protocol Could Be Private",
        files: [
            "Roles.swift": """
            protocol Reading { func read() }
            protocol Writing { func write() }
            typealias Storage = Reading & Writing
            """,
            "Disk.swift": """
            struct DiskStorage: {conformance} {
                func read() {}
                func write() {}
            }
            """,
        ],
        alias: "Storage",
        spelledOut: "Reading, Writing",
        expectedFindings: 0
    ) { files, follow in
        CrossFileVisitorTestSupport.issues(
            of: ProtocolCouldBePrivateVisitor.self, pattern: ProtocolCouldBePrivate().pattern,
            files: files, followingAliases: follow
        )
    }
}

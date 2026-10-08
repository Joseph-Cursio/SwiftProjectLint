@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// An actor is exempt from `Concrete Type Usage` until the project has already abstracted it
/// without losing its isolation.
///
/// The exemption exists because a protocol in front of an actor *can* drop the isolation
/// contract: a synchronous requirement is satisfiable only by a `nonisolated` member or a
/// `@preconcurrency` conformance, and either way a caller reaches it without `await`. A project
/// protocol whose every instance requirement is `async` cannot — callers through it still
/// `await`, and Swift 6 rejects an actor-isolated member satisfying a synchronous requirement.
///
/// Reported against Checkout's `solid/d-concrete-dependency` branch: `CheckoutViewModel` stored
/// and took `CoreDataOrderStore`, an actor conforming to `protocol OrderStore: Sendable` whose two
/// requirements are both `async`, and the rule stayed silent.
@Suite("An actor with an all-async project protocol is reported when used concretely")
struct ConcreteTypeUsageActorTests {

    /// The catalog the pre-scan builds over `sources`, one parsed file each.
    private func catalog(_ sources: String...) -> ActorTypeCatalog {
        ActorTypeCatalog.build(from: sources.map { Parser.parse(source: $0) })
    }

    private func issues(_ source: String, actors: ActorTypeCatalog) -> [LintIssue] {
        let visitor = ConcreteTypeUsageVisitor(patternCategory: .architecture)
        visitor.knownActorTypes = actors
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "Subject.swift", tree: syntax)
        )
        visitor.setFilePath("Subject.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.concreteTypeUsage }
    }

    // MARK: - The reproduction

    private let orderStore = """
    protocol OrderStore: Sendable {
        func save(_ order: Order) async throws
        func recentOrders() async throws -> [Order]
    }
    """

    private let coreDataOrderStore = """
    actor CoreDataOrderStore: OrderStore {
        func save(_ order: Order) async throws { }
        func recentOrders() async throws -> [Order] { [] }
    }
    """

    private let viewModel = """
    final class CheckoutViewModel {
        private let store: CoreDataOrderStore
        init(store: CoreDataOrderStore) { self.store = store }
    }
    """

    @Test("the Checkout reproduction is reported once, naming the protocol it could use")
    func checkoutReproductionIsReported() throws {
        let built = catalog(orderStore, coreDataOrderStore, viewModel)
        #expect(built.contains("CoreDataOrderStore"))
        #expect(built.asyncProtocols(conformedToBy: "CoreDataOrderStore") == ["OrderStore"])

        // The property and its mirroring init parameter are one coupling point, reported once.
        let found = issues(viewModel, actors: built)
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.message.contains("'store'"))
        #expect(issue.message.contains("CoreDataOrderStore"))
        #expect(issue.suggestion?.contains("'OrderStore'") == true)
        #expect(issue.suggestion?.contains("async") == true)
    }

    @Test("a parameter typed with the actor is reported too")
    func parameterIsReported() throws {
        let caller = """
        final class Checkout {
            func place(using store: CoreDataOrderStore) async { }
        }
        """
        let found = issues(caller, actors: catalog(orderStore, coreDataOrderStore))
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.message.contains("Parameter 'using'"))
        #expect(issue.suggestion?.contains("'OrderStore'") == true)
    }

    @Test("a conformance declared in an extension in another file counts")
    func extensionConformanceCounts() {
        let bareActor = """
        actor CoreDataOrderStore {
            func save(_ order: Order) async throws { }
            func recentOrders() async throws -> [Order] { [] }
        }
        """
        let conformance = "extension CoreDataOrderStore: OrderStore {}"
        let built = catalog(orderStore, bareActor, conformance)
        #expect(built.asyncProtocols(conformedToBy: "CoreDataOrderStore") == ["OrderStore"])
        #expect(issues(viewModel, actors: built).count == 1)
    }

    // MARK: - The exemption that stays

    @Test("an actor conforming to no project protocol stays exempt")
    func unconformedActorStaysExempt() {
        let bareActor = "actor CoreDataOrderStore { func save() async { } }"
        let built = catalog(bareActor, viewModel)
        #expect(built.contains("CoreDataOrderStore"))
        #expect(built.asyncProtocols(conformedToBy: "CoreDataOrderStore").isEmpty)
        #expect(issues(viewModel, actors: built).isEmpty)
    }

    @Test("an actor whose project protocol has a synchronous requirement stays exempt")
    func synchronousRequirementKeepsExemption() {
        // `count` is satisfiable only by a `nonisolated` member, and a caller reaches it without
        // `await` — exactly the loss of isolation the exemption guards against.
        let mixed = """
        protocol OrderStore: Sendable {
            func save(_ order: Order) async throws
            var count: Int { get }
        }
        """
        let built = catalog(mixed, coreDataOrderStore)
        #expect(built.asyncProtocols(conformedToBy: "CoreDataOrderStore").isEmpty)
        #expect(issues(viewModel, actors: built).isEmpty)
    }

    @Test("without the catalog's async-protocol half, the actor was silent — the defect")
    func actorNamesAloneKeepTheOldSilence() {
        // The control: what every run before this change did. An actor known only by name keeps
        // the exemption, so an empty finding list here is the exemption working, not the visitor
        // reporting nothing for some other reason — `checkoutReproductionIsReported` is the same
        // source, reported.
        let namesOnly = ActorTypeCatalog(actors: ["CoreDataOrderStore"])
        #expect(issues(viewModel, actors: namesOnly).isEmpty)
    }

    @Test("an actor named inside its own declaration or extension is not a caller depending on it")
    func selfReferenceStaysExempt() {
        // `swift-aws-lambda-runtime`'s shape: a writer nested in the actor holds its owner and
        // calls members the protocol does not carry. The protocol is for callers; this is the
        // actor's own implementation.
        let selfReferencing = """
        actor CoreDataOrderStore: OrderStore {
            struct Writer {
                private var store: CoreDataOrderStore
            }
            func save(_ order: Order) async throws { }
            func recentOrders() async throws -> [Order] { [] }
        }
        extension CoreDataOrderStore {
            func merge(from other: CoreDataOrderStore) async { }
        }
        """
        let built = catalog(orderStore, selfReferencing)
        #expect(built.asyncProtocols(conformedToBy: "CoreDataOrderStore") == ["OrderStore"])
        #expect(issues(selfReferencing, actors: built).isEmpty)
        // The control: the same catalog still reports the actor from outside it.
        #expect(issues(viewModel, actors: built).count == 1)
    }

    // MARK: - What counts as all-async

    @Test("an awaited property requirement counts; a plain getter does not")
    func propertyRequirements() {
        let awaitedGetter = """
        protocol OrderStore { var recent: [Order] { get async throws } }
        actor CoreDataOrderStore: OrderStore { var recent: [Order] { [] } }
        """
        let plainGetter = """
        protocol OrderStore { var recent: [Order] { get } }
        actor CoreDataOrderStore: OrderStore { nonisolated var recent: [Order] { [] } }
        """
        #expect(catalog(awaitedGetter).asyncProtocols(conformedToBy: "CoreDataOrderStore") == ["OrderStore"])
        #expect(catalog(plainGetter).asyncProtocols(conformedToBy: "CoreDataOrderStore").isEmpty)
    }

    @Test("init, static and associated-type requirements neither qualify nor disqualify")
    func typeLevelRequirementsAreNeutral() {
        // None of them is isolated to an instance: an actor's initialiser and its static members
        // are nonisolated by definition.
        let withTypeLevel = """
        protocol OrderStore {
            associatedtype Record
            init(inMemory: Bool)
            static func makeDefault() -> Self
            func save(_ record: Record) async throws
        }
        actor CoreDataOrderStore: OrderStore { }
        """
        let onlyTypeLevel = """
        protocol OrderStore { init(inMemory: Bool) }
        actor CoreDataOrderStore: OrderStore { }
        """
        #expect(catalog(withTypeLevel).asyncProtocols(conformedToBy: "CoreDataOrderStore") == ["OrderStore"])
        #expect(catalog(onlyTypeLevel).asyncProtocols(conformedToBy: "CoreDataOrderStore").isEmpty)
    }

    @Test("a requirement-free protocol is not an abstraction of the actor")
    func markerProtocolDoesNotQualify() {
        // `any OrderStore` would offer the caller nothing to call.
        let marker = """
        protocol OrderStore: Sendable { }
        actor CoreDataOrderStore: OrderStore { }
        """
        #expect(catalog(marker).asyncProtocols(conformedToBy: "CoreDataOrderStore").isEmpty)
    }

    @Test("inherited requirements count, and an all-async ancestor is reachable through a sync child")
    func inheritance() {
        let hierarchy = """
        protocol OrderStore: Sendable { func save(_ order: Order) async throws }
        protocol CountingOrderStore: OrderStore { var count: Int { get } }
        protocol ArchivingOrderStore: OrderStore { func archive() async }
        actor CoreDataOrderStore: CountingOrderStore { }
        actor ArchiveStore: ArchivingOrderStore { }
        """
        let built = catalog(hierarchy)
        // `CountingOrderStore` is out — its own requirement is synchronous — but the actor
        // conforms to `OrderStore` through it, and that one is all-async.
        #expect(built.asyncProtocols(conformedToBy: "CoreDataOrderStore") == ["OrderStore"])
        #expect(built.asyncProtocols(conformedToBy: "ArchiveStore") == ["ArchivingOrderStore", "OrderStore"])
    }

    @Test("a synchronous requirement inherited from a project parent disqualifies the child")
    func inheritedSynchronousRequirementDisqualifies() {
        let hierarchy = """
        protocol Counting { var count: Int { get } }
        protocol OrderStore: Counting { func save(_ order: Order) async throws }
        actor CoreDataOrderStore: OrderStore { }
        """
        #expect(catalog(hierarchy).asyncProtocols(conformedToBy: "CoreDataOrderStore").isEmpty)
    }

    @Test("a parent outside the project counts as synchronous unless it is a marker")
    func foreignParents() {
        // `Identifiable` requires a synchronous `id`; `Sendable` and `Actor` add nothing an
        // isolated member could leak through.
        let foreign = """
        protocol OrderStore: Identifiable { func save(_ order: Order) async throws }
        actor CoreDataOrderStore: OrderStore { }
        """
        let markers = """
        protocol OrderStore: Actor, Sendable { func save(_ order: Order) async throws }
        actor CoreDataOrderStore: OrderStore { }
        """
        let whereClause = """
        protocol OrderStore where Self: Identifiable { func save(_ order: Order) async throws }
        actor CoreDataOrderStore: OrderStore { }
        """
        #expect(catalog(foreign).asyncProtocols(conformedToBy: "CoreDataOrderStore").isEmpty)
        #expect(catalog(markers).asyncProtocols(conformedToBy: "CoreDataOrderStore") == ["OrderStore"])
        #expect(catalog(whereClause).asyncProtocols(conformedToBy: "CoreDataOrderStore").isEmpty)
    }

    @Test("a fileprivate protocol is not one a caller in another file could use")
    func fileLocalProtocolDoesNotQualify() {
        let fileLocal = """
        fileprivate protocol OrderStore { func save(_ order: Order) async throws }
        actor CoreDataOrderStore: OrderStore { }
        """
        #expect(catalog(fileLocal).asyncProtocols(conformedToBy: "CoreDataOrderStore").isEmpty)
    }

    @Test("qualified, attributed and composed conformances are all read")
    func conformanceSpellings() {
        let protocols = """
        protocol OrderStore { func save(_ order: Order) async throws }
        protocol Archiving { func archive() async }
        """
        let spellings = """
        actor Qualified: Domain.OrderStore { }
        actor Attributed: @preconcurrency OrderStore { }
        actor Composed: OrderStore & Archiving { }
        """
        let built = catalog(protocols, spellings)
        #expect(built.asyncProtocols(conformedToBy: "Qualified") == ["OrderStore"])
        #expect(built.asyncProtocols(conformedToBy: "Attributed") == ["OrderStore"])
        #expect(built.asyncProtocols(conformedToBy: "Composed") == ["Archiving", "OrderStore"])
    }

    @Test("a class conforming to the same protocol is not an actor and is not catalogued")
    func classesAreNotCatalogued() {
        let classConformer = "final class SQLiteOrderStore: OrderStore { }"
        let built = catalog(orderStore, classConformer)
        #expect(built.contains("SQLiteOrderStore") == false)
        #expect(built.asyncProtocols(conformedToBy: "SQLiteOrderStore").isEmpty)
    }

    // MARK: - End to end

    /// The catalog has to reach the visitor through the pre-scan, the detector and the per-file
    /// environment. Each file holds one of the three facts the join needs; the control actor in
    /// the same run conforms to nothing, proving the exemption still applies where it should.
    @Test("the pre-scan carries the conformance across files to the rule")
    func endToEnd() async {
        let root = makePackage(named: "ActorSeam", files: [
            "Domain/OrderStore.swift": orderStore + "\nstruct Order { }",
            "Persistence/CoreDataOrderStore.swift": """
            actor CoreDataOrderStore {
                func save(_ order: Order) async throws { }
                func recentOrders() async throws -> [Order] { [] }
            }
            """,
            "Persistence/CoreDataOrderStore+OrderStore.swift":
                "extension CoreDataOrderStore: OrderStore {}",
            "Persistence/AuditLogStore.swift": "actor AuditLogStore { func append() async { } }",
            "Presentation/CheckoutViewModel.swift": """
            final class CheckoutViewModel {
                private let store: CoreDataOrderStore
                private let audit: AuditLogStore
                init(store: CoreDataOrderStore, audit: AuditLogStore) {
                    self.store = store
                    self.audit = audit
                }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }

        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await ProjectLinter().analyzeProject(at: root, detector: system.detector)
        let concrete = issues.filter { $0.ruleName == .concreteTypeUsage }

        #expect(concrete.count == 1)
        #expect(concrete.contains { $0.message.contains("CoreDataOrderStore") })
        #expect(concrete.contains { $0.message.contains("AuditLogStore") } == false)
    }

    private func makePackage(named name: String, files: [String: String]) -> String {
        let base = FileManager.default.temporaryDirectory.path
        let root = (base as NSString).appendingPathComponent("\(name)-\(UUID().uuidString)")
        write("// swift-tools-version:6.0\n", to: "\(root)/Package.swift")
        for (path, content) in files {
            write(content, to: "\(root)/Sources/\(name)/\(path)")
        }
        return root
    }

    private func write(_ content: String, to path: String) {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

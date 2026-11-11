import Foundation
import SwiftProjectLintEngine
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import Testing

extension ConcreteTypeUsageActorTests {
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
            """,
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
        let root = PathString.appending("\(name)-\(UUID().uuidString)", to: base)
        write("// swift-tools-version:6.0\n", to: "\(root)/Package.swift")
        for (path, content) in files {
            write(content, to: "\(root)/Sources/\(name)/\(path)")
        }
        return root
    }

    private func write(_ content: String, to path: String) {
        try? FileManager.default.createDirectory(
            atPath: PathString.deletingLastComponent(of: path),
            withIntermediateDirectories: true
        )
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

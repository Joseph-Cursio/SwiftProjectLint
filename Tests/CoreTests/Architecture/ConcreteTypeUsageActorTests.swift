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
    func catalog(_ sources: String...) -> ActorTypeCatalog {
        ActorTypeCatalog.build(from: sources.map { Parser.parse(source: $0) })
    }

    func issues(_ source: String, actors: ActorTypeCatalog) -> [LintIssue] {
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

    let orderStore = """
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
}

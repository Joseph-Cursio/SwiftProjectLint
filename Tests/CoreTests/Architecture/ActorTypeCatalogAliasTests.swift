@testable import Core
import SwiftParser
import SwiftProjectLintVisitors
import Testing

/// An actor conforming through a composition `typealias` conforms to every role the alias
/// composes, so `Concrete Type Usage` sees the all-`async` protocols it could be typed as.
///
/// Without the expansion, `actor CoreDataOrderStore: OrderStore` looked up `OrderStore` as a
/// protocol, found none, and kept the actor exemption that the spelled-out conformance loses.
@Suite
struct ActorTypeCatalogAliasTests {

    private let roles = """
    protocol OrderSaving: Sendable { func save(_ order: Order) async throws }
    protocol OrderHistory: Sendable { func recentOrders() async throws -> [Order] }
    typealias OrderStore = OrderSaving & OrderHistory
    """

    private func catalog(_ sources: String...) -> ActorTypeCatalog {
        let trees = sources.map { Parser.parse(source: $0) }
        return ActorTypeCatalog.build(from: trees, aliases: CompositionAliasCatalog.build(from: trees))
    }

    @Test(arguments: [
        "actor CoreDataOrderStore: OrderStore {}",
        "actor CoreDataOrderStore: OrderSaving, OrderHistory {}",
        "actor CoreDataOrderStore {}\nextension CoreDataOrderStore: OrderStore {}"
    ])
    func everySpellingConformsToBothRoles(actor: String) {
        let built = catalog(roles, actor)
        #expect(built.asyncProtocols(conformedToBy: "CoreDataOrderStore") == ["OrderHistory", "OrderSaving"])
    }

    @Test
    func aProtocolRefiningTheAliasInheritsItsRoles() {
        // Read by name, `OrderStore` was a parent this run could not see — synchronous by
        // assumption — so `RichStore` did not qualify either.
        let built = catalog(
            roles,
            "protocol RichStore: OrderStore { func purge() async }",
            "actor CoreDataOrderStore: RichStore {}"
        )
        #expect(built.asyncProtocols(conformedToBy: "CoreDataOrderStore") == [
            "OrderHistory", "OrderSaving", "RichStore"
        ])
    }

    @Test
    func anAliasWithASynchronousRoleQualifiesOnlyTheAsyncOne() {
        let built = catalog(
            """
            protocol OrderSaving: Sendable { func save(_ order: Order) async throws }
            protocol OrderCounting { var count: Int { get } }
            typealias OrderStore = OrderSaving & OrderCounting
            """,
            "actor CoreDataOrderStore: OrderStore {}"
        )
        #expect(built.asyncProtocols(conformedToBy: "CoreDataOrderStore") == ["OrderSaving"])
    }
}

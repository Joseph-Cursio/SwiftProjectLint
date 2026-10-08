@testable import Core
import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// `CompositionAliasCatalog` resolves `typealias OrderStore = OrderSaving & OrderHistory` to the
/// names it stands for, so a conformance written through the alias is a conformance to each.
@Suite
struct CompositionAliasCatalogTests {

    private func catalog(_ sources: String...) -> CompositionAliasCatalog {
        CompositionAliasCatalog.build(from: sources.map { Parser.parse(source: $0) })
    }

    @Test
    func compositionExpandsToItsComponents() {
        let aliases = catalog("""
        protocol OrderSaving: Sendable {}
        protocol OrderHistory: Sendable {}
        typealias OrderStore = OrderSaving & OrderHistory
        """)
        #expect(aliases.expand("OrderStore") == ["OrderSaving", "OrderHistory"])
        #expect(aliases.isAlias("OrderStore"))
    }

    @Test
    func aNameThatIsNotAnAliasExpandsToItself() {
        let aliases = catalog("protocol OrderSaving {}")
        #expect(aliases.expand("OrderSaving") == ["OrderSaving"])
        #expect(aliases.isAlias("OrderSaving") == false)
    }

    @Test
    func nestedAliasesResolveTransitively() {
        // Declared out of order and across files: resolution does not depend on either.
        let aliases = catalog(
            "typealias OrderStore = Reading & OrderSaving",
            "typealias Reading = OrderHistory & OrderSearching"
        )
        #expect(aliases.expand("OrderStore") == ["OrderHistory", "OrderSearching", "OrderSaving"])
    }

    @Test
    func aComponentReachedTwiceIsListedOnce() {
        let aliases = catalog("""
        typealias Reading = OrderHistory & Sendable
        typealias OrderStore = Reading & OrderSaving & Sendable
        """)
        #expect(aliases.expand("OrderStore") == ["OrderHistory", "Sendable", "OrderSaving"])
    }

    @Test
    func anyAndAPlainRenameAreBothCatalogued() {
        let aliases = catalog("""
        typealias AnyStore = any OrderSaving & OrderHistory
        typealias LegacyStore = OrderSaving
        """)
        #expect(aliases.expand("AnyStore") == ["OrderSaving", "OrderHistory"])
        #expect(aliases.expand("LegacyStore") == ["OrderSaving"])
    }

    @Test
    func aliasesForOtherShapesAreLeftAlone() {
        let aliases = catalog("""
        typealias Handler = (Int) -> Void
        typealias Stores = [OrderSaving]
        typealias Box = Wrapper<OrderSaving>
        typealias Qualified = Swift.Sendable & OrderSaving
        typealias Maybe = OrderSaving?
        typealias Pair<T> = OrderSaving & Container<T>
        """)
        #expect(aliases.isEmpty)
    }

    @Test
    func aNameDefinedTwoWaysIsNotExpanded() {
        // Two nested `Element` aliases mean different things; a rule seeing only the name cannot
        // tell which one it is looking at.
        let aliases = catalog(
            "struct A { typealias Element = OrderSaving }",
            "struct B { typealias Element = OrderHistory }"
        )
        #expect(aliases.expand("Element") == ["Element"])
    }

    @Test
    func aNameDefinedTwiceTheSameWayIsExpanded() {
        let aliases = catalog(
            "typealias OrderStore = OrderSaving & OrderHistory",
            "typealias OrderStore = OrderSaving & OrderHistory"
        )
        #expect(aliases.expand("OrderStore") == ["OrderSaving", "OrderHistory"])
    }

    @Test(arguments: [
        "protocol Store {}",
        "struct Store {}",
        "final class Store {}",
        "enum Store {}",
        "actor Store {}",
        "protocol Feature { associatedtype Store }",
        "func make<Store: OrderSaving>(_ store: Store) {}",
        "typealias Store<T> = Box<T>",
        "typealias Store = () -> Void"
    ])
    func aNameAlsoDeclaredAnotherWayIsNotExpanded(other: String) {
        let aliases = catalog("struct Outer { typealias Store = OrderSaving & OrderHistory }", other)
        #expect(aliases.expand("Store") == ["Store"])
    }

    @Test
    func aCycleIsDropped() {
        let aliases = catalog("""
        typealias First = Second & OrderSaving
        typealias Second = First & OrderHistory
        typealias Third = First & OrderAdministration
        """)
        #expect(aliases.isEmpty)
    }

    @Test
    func anAmbiguousComponentIsKeptAsAName() {
        let aliases = catalog(
            "typealias OrderStore = Element & OrderSaving",
            "struct A { typealias Element = OrderHistory }",
            "struct B { typealias Element = OrderAdministration }"
        )
        #expect(aliases.expand("OrderStore") == ["Element", "OrderSaving"])
    }

    @Test
    func abstractionAliasesAreExistentialsAndRenamesOfProtocols() {
        let aliases = catalog("""
        typealias OrderStore = OrderSaving & OrderHistory
        typealias AnyStore = any OrderSaving
        typealias LegacyStore = OrderSaving
        typealias Model = UserRecord
        typealias ViaComposition = OrderStore
        """)
        #expect(aliases.abstractionAliases(protocols: ["OrderSaving", "OrderHistory"]) == [
            "OrderStore", "AnyStore", "LegacyStore", "ViaComposition"
        ])
    }

    @Test
    func emptyExpandsEveryNameToItself() {
        #expect(CompositionAliasCatalog.empty.expand("OrderStore") == ["OrderStore"])
        #expect(CompositionAliasCatalog.empty.isEmpty)
    }
}

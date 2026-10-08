@testable import Core
import Testing

/// A conformance written through a composition `typealias` is a conformance to every protocol
/// the alias composes.
///
/// Found on Checkout's `solid/i-split-store`: with `actor CoreDataOrderStore: OrderStore`, the
/// rule reported all four roles as having *no* conformers, because it read the alias's own name.
/// Writing the conformance out gave the right answer. These pin the two spellings together.
@Suite
struct SingleImplementationProtocolAliasTests {

    /// Checkout's split store, with the store's conformance spelled `conformance`.
    private func checkout(conformance: String) -> [String: String] {
        [
            "Domain/OrderStore.swift": """
            protocol OrderSaving: Sendable {
                func save(_ order: Order) async throws
            }
            protocol OrderHistory: Sendable {
                func recentOrders() async throws -> [Order]
            }
            protocol OrderAdministration: Sendable {
                func deleteAll() async throws
            }
            protocol AnalyticsRecording: Sendable {
                func recordAnalyticsEvent(_ name: String) async
            }
            typealias OrderStore = OrderSaving & OrderHistory & OrderAdministration & AnalyticsRecording
            """,
            "Persistence/CoreDataOrderStore.swift": """
            actor CoreDataOrderStore: \(conformance) {
                func save(_ order: Order) async throws {}
                func recentOrders() async throws -> [Order] { [] }
                func deleteAll() async throws {}
                func recordAnalyticsEvent(_ name: String) async {}
            }
            """,
            "Presentation/CheckoutViewModel.swift": """
            final class CheckoutViewModel {
                private let store: any OrderSaving
                init(store: any OrderSaving) { self.store = store }
            }
            """
        ]
    }

    private func analyze(_ files: [String: String]) -> [LintIssue] {
        SingleImplementationProtocolTestSupport.analyze(files: files)
    }

    @Test
    func conformingThroughTheAliasCountsAsConformingToEveryRole() {
        let messages = analyze(checkout(conformance: "OrderStore")).map(\.message).sorted()

        // `OrderSaving` has a client, so its single conformer is a seam. The other three roles
        // have one conformer and no client — what the essay reports — and none has "no conformers".
        #expect(messages == [
            "Protocol 'AnalyticsRecording' has only one conformer ('CoreDataOrderStore') — "
                + "consider removing the abstraction.",
            "Protocol 'OrderAdministration' has only one conformer ('CoreDataOrderStore') — "
                + "consider removing the abstraction.",
            "Protocol 'OrderHistory' has only one conformer ('CoreDataOrderStore') — "
                + "consider removing the abstraction."
        ])
    }

    @Test
    func theAliasAndTheWrittenOutConformanceAgree() {
        let throughAlias = analyze(checkout(conformance: "OrderStore"))
        let writtenOut = analyze(checkout(
            conformance: "OrderSaving, OrderHistory, OrderAdministration, AnalyticsRecording"
        ))
        #expect(throughAlias.map(\.message).sorted() == writtenOut.map(\.message).sorted())
    }

    @Test(arguments: [
        "any OrderStore",
        "OrderStore",
        "(any OrderStore)?",
        "any OrderSaving & OrderHistory & OrderAdministration & AnalyticsRecording"
    ])
    func aDependencyTypedWithTheCompositionConsumesEveryRole(dependency: String) {
        var files = checkout(conformance: "OrderStore")
        files["Presentation/AdminViewModel.swift"] = """
        final class AdminViewModel {
            private let store: \(dependency)
            init(store: \(dependency)) { self.store = store }
        }
        """
        #expect(analyze(files).isEmpty)
    }

    @Test
    func anInlineCompositionConsumesOnlyTheProtocolsItNames() {
        var files = checkout(conformance: "OrderStore")
        files["Presentation/HistoryViewModel.swift"] = """
        final class HistoryViewModel {
            private let store: any OrderSaving & OrderHistory
        }
        """
        let messages = analyze(files).map(\.message).sorted()
        #expect(messages.count == 2)
        #expect(messages.first?.contains("'AnalyticsRecording'") == true)
        #expect(messages.last?.contains("'OrderAdministration'") == true)
    }

    @Test
    func anExtensionConformingThroughTheAliasCounts() {
        let issues = analyze([
            "Roles.swift": """
            protocol Reading { func read() }
            protocol Writing { func write() }
            typealias Storage = Reading & Writing
            """,
            "Disk.swift": "struct DiskStorage {}",
            "Disk+Storage.swift": "extension DiskStorage: Storage {}",
            "Memory.swift": "struct MemoryStorage: Storage {}"
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func anAliasOfAnAliasIsFollowedThrough() {
        let issues = analyze([
            "Roles.swift": """
            protocol Reading { func read() }
            protocol Writing { func write() }
            typealias ReadOnly = Reading & Sendable
            typealias Storage = ReadOnly & Writing
            """,
            "Disk.swift": "struct DiskStorage: Storage {}",
            "Memory.swift": "struct MemoryStorage: Storage {}"
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func aMockConformingThroughTheAliasExemptsEveryRole() {
        let issues = analyze([
            "Roles.swift": """
            protocol Reading { func read() }
            protocol Writing { func write() }
            typealias Storage = Reading & Writing
            """,
            "Disk.swift": "struct DiskStorage: Storage {}",
            "Tests/MockStorage.swift": "struct MockStorage: Storage {}"
        ])
        #expect(issues.isEmpty)
    }
}

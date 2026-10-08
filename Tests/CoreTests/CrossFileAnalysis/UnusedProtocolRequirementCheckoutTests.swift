@testable import Core
import Testing

/// The reproduction target: Checkout's `OrderStore`, on the branches the SOLID essay uses.
@Suite
struct UnusedProtocolRequirementCheckoutTests {

    private static let fatStore = """
    import Foundation

    protocol OrderStore: Sendable {
        func save(_ order: Order) async throws
        func recentOrders() async throws -> [Order]
        func order(withIdentifier identifier: UUID) async throws -> Order?
        func cancel(_ identifier: UUID) async throws
        func refund(_ identifier: UUID, amount: Money) async throws
        func receiptText(for identifier: UUID) async throws -> String
        func exportCSV() async throws -> String
        func orderCount() async throws -> Int
        func deleteAll() async throws
        func recordAnalyticsEvent(_ name: String) async
    }
    """

    private static let viewModel = """
    import Foundation
    import Observation

    @MainActor
    @Observable
    final class CheckoutViewModel {
        private let store: any OrderStore
        private(set) var order: Order
        private(set) var lastError: String?

        init(store: any OrderStore) {
            self.store = store
            order = Order(identifier: UUID(), items: [], paymentMethod: .card, discount: nil)
        }

        func placeOrder() async {
            do {
                try await store.save(order)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
    """

    private static let conformer = """
    actor CoreDataOrderStore: OrderStore {
        func save(_ order: Order) async throws {}
        func recentOrders() async throws -> [Order] { [] }
        func order(withIdentifier identifier: UUID) async throws -> Order? { nil }
        func cancel(_ identifier: UUID) async throws {}
        func refund(_ identifier: UUID, amount: Money) async throws {}
        func receiptText(for identifier: UUID) async throws -> String {
            guard let order = try await order(withIdentifier: identifier) else { return "" }
            return "\\(order)"
        }
        func exportCSV() async throws -> String { "" }
        func orderCount() async throws -> Int { 0 }
        func deleteAll() async throws {}
        func recordAnalyticsEvent(_ name: String) async {}
    }
    """

    private static let app = """
    import SwiftUI

    @main
    struct CheckoutApp: App {
        private let store = CoreDataOrderStore()

        var body: some Scene {
            WindowGroup {
                CheckoutView(model: CheckoutViewModel(store: store))
            }
        }
    }
    """

    /// `solid/i-fat-store`: one client, which calls `save` and nothing else.
    @Test
    func fatStoreReportsTheNineRequirementsNoClientCalls() throws {
        let files = [
            "Domain/OrderStore.swift": Self.fatStore,
            "Presentation/CheckoutViewModel.swift": Self.viewModel,
            "Persistence/CoreDataOrderStore.swift": Self.conformer,
            "App/CheckoutApp.swift": Self.app
        ]

        #expect(UnusedRequirementHarness.reported(files) == [
            "OrderStore.cancel(_:)",
            "OrderStore.deleteAll()",
            "OrderStore.exportCSV()",
            "OrderStore.order(withIdentifier:)",
            "OrderStore.orderCount()",
            "OrderStore.receiptText(for:)",
            "OrderStore.recentOrders()",
            "OrderStore.recordAnalyticsEvent(_:)",
            "OrderStore.refund(_:amount:)"
        ])

        let issues = UnusedRequirementHarness.issues(files)
        let recent = try #require(issues.first { $0.message.contains("'recentOrders()'") })
        #expect(recent.filePath == "Domain/OrderStore.swift")
        #expect(recent.lineNumber == 5)
        #expect(recent.severity == .info)
        #expect(recent.message.contains("its clients use 1 of its 10 requirements"))
    }

    /// `main`: two requirements, and only `save` is called through the protocol.
    @Test
    func mainReportsRecentOrders() {
        let store = """
        protocol OrderStore: Sendable {
            func save(_ order: Order) async throws
            func recentOrders() async throws -> [Order]
        }
        """
        let files = ["OrderStore.swift": store, "CheckoutViewModel.swift": Self.viewModel]

        #expect(UnusedRequirementHarness.reported(files) == ["OrderStore.recentOrders()"])
    }

    /// `essay/s3-layer-violation` calls `recentOrders()` — on a `CoreDataOrderStore` it built
    /// itself. That depends on the conformer, not on the protocol, so the requirement is still
    /// one no client uses through `OrderStore`.
    @Test
    func callOnAConcreteConformerDoesNotCount() {
        let store = """
        protocol OrderStore: Sendable {
            func save(_ order: Order) async throws
            func recentOrders() async throws -> [Order]
        }
        """
        let layerViolation = """
        final class CheckoutViewModel {
            private let store: any OrderStore
            init(store: any OrderStore) { self.store = store }

            func placeOrder(_ order: Order) async throws {
                try await store.save(order)
                let history = CoreDataOrderStore()
                if let last = try? await history.recentOrders().first {
                    print(last)
                }
            }
        }
        """
        let files = [
            "OrderStore.swift": store,
            "CheckoutViewModel.swift": layerViolation,
            "CoreDataOrderStore.swift": Self.conformer
        ]

        #expect(UnusedRequirementHarness.reported(files) == ["OrderStore.recentOrders()"])
    }

    /// `solid/i-split-store`: the view model depends on `OrderSaving` and calls its one
    /// requirement; the other three roles have no clients at all, which is
    /// `Unused Protocol Abstraction`'s finding, not this rule's.
    @Test
    func splitStoreReportsNothing() {
        let roles = """
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
        """
        let viewModel = """
        final class CheckoutViewModel {
            private let store: any OrderSaving
            init(store: any OrderSaving) { self.store = store }
            func placeOrder(_ order: Order) async throws { try await store.save(order) }
        }
        """

        #expect(UnusedRequirementHarness.reported(["Roles.swift": roles, "VM.swift": viewModel]).isEmpty)
    }
}

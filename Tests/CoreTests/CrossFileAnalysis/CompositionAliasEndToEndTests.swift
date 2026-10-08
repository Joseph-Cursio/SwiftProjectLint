@testable import Core
import Foundation
import Testing

/// Checkout's split store, end to end: the conformance written through
/// `typealias OrderStore = OrderSaving & OrderHistory & …` reaches every rule through a real
/// `ProjectLinter` run — the cross-file engine's shared alias catalog and the per-file pre-scan
/// alike.
@Suite
struct CompositionAliasEndToEndTests {

    @Test
    func theSplitStoreConformingThroughTheAliasReportsWhatTheEssayReports() async {
        let root = makePackage(named: "SplitStore", files: Self.splitStore)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let issues = await analyze(root)
        let singleImplementation = issues
            .filter { $0.ruleName == .singleImplementationProtocol }
            .map(\.message)

        #expect(singleImplementation.contains { $0.contains("no conformers") } == false)
        #expect(singleImplementation.sorted() == [
            "Protocol 'AnalyticsRecording' has only one conformer ('CoreDataOrderStore') — "
                + "consider removing the abstraction.",
            "Protocol 'OrderAdministration' has only one conformer ('CoreDataOrderStore') — "
                + "consider removing the abstraction.",
            "Protocol 'OrderHistory' has only one conformer ('CoreDataOrderStore') — "
                + "consider removing the abstraction."
        ])
    }

    @Test
    func aPropertyTypedWithTheAliasIsAnAbstraction() async {
        var files = Self.splitStore
        files["Sources/Checkout/Presentation/ReceiptPrinter.swift"] = """
        final class ReceiptPrinter {
            private let store: OrderStore
            private let disk: DiskOrderStore
            init(store: OrderStore, disk: DiskOrderStore) {
                self.store = store
                self.disk = disk
            }
        }

        final class DiskOrderStore {
            private var orders: [Order] = []
            func save(_ order: Order) { orders.append(order) }
        }
        """
        let root = makePackage(named: "AliasProperty", files: files)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let concrete = await analyze(root)
            .filter { $0.ruleName == .concreteTypeUsage }
            .map(\.message)

        // `Store` is a service suffix, so the alias read as a concrete service. The control
        // beside it shows the rule is live in this run.
        #expect(concrete.contains { $0.contains("'OrderStore'") } == false)
        #expect(concrete.contains { $0.contains("'DiskOrderStore'") })
    }

    // MARK: - Fixture

    private static let splitStore: [String: String] = [
        "Sources/Checkout/Domain/OrderStore.swift": """
        import Foundation

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

        struct Order: Sendable {}
        """,
        "Sources/Checkout/Persistence/CoreDataOrderStore.swift": """
        actor CoreDataOrderStore: OrderStore {
            func save(_ order: Order) async throws {}
            func recentOrders() async throws -> [Order] { [] }
            func deleteAll() async throws {}
            func recordAnalyticsEvent(_ name: String) async {}
        }
        """,
        "Sources/Checkout/Presentation/CheckoutViewModel.swift": """
        final class CheckoutViewModel {
            private let store: any OrderSaving
            init(store: any OrderSaving) { self.store = store }
            func checkout() async throws { try await store.save(Order()) }
        }
        """
    ]

    private func analyze(_ root: String) async -> [LintIssue] {
        let system = PatternRegistryFactory.createConfiguredSystem()
        return await ProjectLinter().analyzeProject(at: root, detector: system.detector)
    }

    private func makePackage(named name: String, files: [String: String]) -> String {
        let base = FileManager.default.temporaryDirectory.path
        let root = (base as NSString).appendingPathComponent("\(name)-\(UUID().uuidString)")
        write("// swift-tools-version:6.0\n", to: "\(root)/Package.swift")
        for (path, content) in files {
            write(content, to: "\(root)/\(path)")
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

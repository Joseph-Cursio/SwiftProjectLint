@testable import Core
import Foundation
import Testing

/// `Protocol Naming Suffix` is a team naming convention, so it is opt-in.
///
/// Run by default, it reported Checkout's `OrderStore` — a role-noun protocol whose one
/// conformer is `CoreDataOrderStore` and whose every use is spelled `any OrderStore` — and
/// asked for `OrderStoreProtocol`, the naming `Mirror Protocol` describes as the smell's
/// signature. These tests pin the end-to-end wiring on that shape: silent by default,
/// reported when a team lists the rule under `enabled_only`.
struct ProtocolNamingSuffixOptInTests {

    @Test func roleNounProtocolIsNotReportedByDefault() async throws {
        let root = try makeCheckoutShapedPackage()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let issues = await ProjectLinter().analyzeProject(
            at: root,
            detector: PatternRegistryFactory.createConfiguredSystem().detector
        )

        #expect(issues.contains { $0.ruleName == .protocolNamingSuffix } == false)
    }

    @Test func conventionIsEnforcedWhenEnabled() async throws {
        let root = try makeCheckoutShapedPackage()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let issues = await ProjectLinter().analyzeProject(
            at: root,
            detector: PatternRegistryFactory.createConfiguredSystem().detector,
            configuration: LintConfiguration(enabledOnlyRules: [.protocolNamingSuffix])
        )

        let flagged = issues.filter { $0.ruleName == .protocolNamingSuffix }
        #expect(flagged.count == 1)
        #expect(flagged.first?.message == "Protocol 'OrderStore' is not suffixed with 'Protocol'")
    }

    @Test func defaultRuleSetExcludesTheRule() throws {
        let rules = try #require(LintConfiguration.default.resolveRules())
        #expect(rules.contains(.protocolNamingSuffix) == false)
    }

    // MARK: - Fixture

    /// Checkout's layering in miniature: `Domain/` owns the protocol, `Persistence/`
    /// conforms to it, `Presentation/` depends on it as `any OrderStore`.
    private func makeCheckoutShapedPackage() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProtocolNamingSuffix-\(UUID().uuidString)").path
        let files = [
            "Package.swift": "// swift-tools-version:6.0\n",
            "Sources/Checkout/Domain/Order.swift": """
            struct Order: Sendable {
                let identifier: Int
            }
            """,
            "Sources/Checkout/Domain/OrderStore.swift": """
            protocol OrderStore: Sendable {
                func save(_ order: Order) async throws
                func recentOrders() async throws -> [Order]
            }
            """,
            "Sources/Checkout/Persistence/CoreDataOrderStore.swift": """
            actor CoreDataOrderStore: OrderStore {
                private var orders: [Order] = []
                func save(_ order: Order) async throws { orders.append(order) }
                func recentOrders() async throws -> [Order] { orders }
            }
            """,
            "Sources/Checkout/Presentation/CheckoutModel.swift": """
            final class CheckoutModel {
                private let store: any OrderStore
                init(store: any OrderStore) { self.store = store }
            }
            """
        ]
        for (relativePath, content) in files {
            let path = (root as NSString).appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        }
        return root
    }
}

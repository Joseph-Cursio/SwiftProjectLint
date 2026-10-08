@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// What `Lossy Round Trip` must not report.
///
/// None of these is hypothetical. Each is a class of false positive the rule produced — on the
/// author's sibling repositories, or on a 48,000-file held-out corpus of third-party and tutorial
/// code — before the gate that excludes it was added.
@Suite("Lossy round trip — what it must not report")
struct LossyRoundTripFalsePositiveTests {

    /// `localTypes` is what `ProjectLinter`'s pre-scan injects: every type the project declares. The
    /// rule only fires on a constructed type in it.
    private func analyze(
        _ source: String,
        filePath: String = "Store.swift",
        localTypes: Set<String> = ["Order", "SkillDraft", "OrderRecord"]
    ) -> [LintIssue] {
        let visitor = LossyRoundTripVisitor(patternCategory: .codeQuality)
        visitor.knownLocalTypeNames = localTypes
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: filePath, tree: syntax))
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .lossyRoundTrip }
    }

    /// The fix on `solid/l-contract-test-fixed`: every field comes back.
    @Test("a store that reads every field back does not fire")
    func completeRoundTripIsSilent() {
        let issues = analyze("""
        actor CoreDataOrderStore {
            func save(_ order: Order) throws {
                let encodedItems = try JSONEncoder().encode(order.items)
                record.setValue(order.identifier, forKey: "identifier")
                record.setValue(encodedItems, forKey: "lineItems")
                record.setValue(order.discount?.value, forKey: "discountCode")
            }

            func recentOrders() throws -> [Order] {
                try context.fetch(request).compactMap { record in
                    guard let identifier = record.value(forKey: "identifier") as? UUID,
                          let encodedItems = record.value(forKey: "lineItems") as? Data,
                          let items = try? JSONDecoder().decode([LineItem].self, from: encodedItems)
                    else { return nil }
                    let discount = (record.value(forKey: "discountCode") as? String).map(DiscountCode.init)
                    return Order(identifier: identifier, items: items, discount: discount)
                }
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    /// The in-memory double every test suite has. It keeps whole values, so nothing is taken apart.
    @Test("a store that keeps whole values does not fire")
    func wholeValueStoreIsSilent() {
        let issues = analyze("""
        actor InMemoryOrderStore {
            private var orders: [Order] = []
            private var byID: [UUID: Order] = [:]

            func save(_ order: Order) {
                orders.append(order)
                byID[order.identifier] = order
            }

            func placeholder(for identifier: UUID) -> Order {
                Order(identifier: identifier, items: [])
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    /// `IndexPath(row: selectedIndex, section: 0)` after storing `indexPath.row` IS a round trip that
    /// drops a field — on purpose, because the table has one section. Every finding of this kind on the
    /// held-out corpus was a framework or dependency type, and every one was intended.
    @Test("a type the project does not declare does not fire")
    func nonLocalTypeIsSilent() {
        let issues = analyze("""
        final class ViewController {
            func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
                selectedIndex = indexPath.row
            }

            func update() {
                tableView.reloadRows(at: [IndexPath(row: selectedIndex, section: 0)], with: .automatic)
            }
        }
        """, localTypes: ["Order"])

        #expect(issues.isEmpty)
    }

    /// Two members that mention one type are not a round trip. The rebuild must read back a slot the
    /// decomposing member wrote.
    @Test("a construction that reads none of the stored slots does not fire")
    func unrelatedConstructionIsSilent() {
        let issues = analyze("""
        final class CheckoutViewModel {
            func select(_ order: Order) {
                selectedID = order.identifier
            }

            func makeDraft() -> Order {
                Order(identifier: UUID(), items: [], discount: nil)
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    /// A guard-`else` fallback built only of constants is a fresh value, not a lossy rebuild, even in a
    /// member that does read the stored keys.
    @Test("an all-constant fallback does not fire")
    func constantFallbackIsSilent() {
        let issues = analyze("""
        final class OrderStore {
            func save(_ order: Order) {
                record.setValue(order.identifier, forKey: "identifier")
            }

            func load() -> Order {
                guard let identifier = record.value(forKey: "identifier") as? UUID else {
                    return Order(identifier: .zero, items: [], discount: nil)
                }
                return Order(identifier: identifier, items: loadItems(), discount: loadDiscount())
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    /// A literal beside a field read is a storage key only when its argument says so. Treated as a key,
    /// `"Swift Evolution"` here paired this copy with an unrelated member showing the same title.
    @Test("an unlabelled literal in a constructor is not a storage key")
    func constructorLiteralIsNotAKey() {
        let issues = analyze("""
        enum CorpusRows {
            static func renamed(_ order: Order) -> Order {
                Order(identifier: order.identifier, title: "Swift Evolution", items: order.items)
            }

            static func unloaded() -> Order {
                Order(identifier: defaultIdentifier, title: "Swift Evolution", items: [])
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    /// `label.text = order.title` is not storage. A property on another object counts only when its
    /// name mirrors the field — `entity.title = order.title`.
    @Test("an assignment into an unrelated property is not a slot")
    func unmirroredAssignmentIsNotASlot() {
        let issues = analyze("""
        final class OrderCell {
            func configure(with order: Order) {
                label.text = order.title
            }

            func preview() -> Order {
                Order(title: label.text, items: [])
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    @Test("an inout parameter is mutated, not decomposed")
    func inoutParameterIsSilent() {
        let issues = analyze("""
        struct OrderReducer {
            func apply(_ state: inout Order) {
                lastIdentifier = state.identifier
            }

            func reset() -> Order {
                Order(identifier: lastIdentifier, items: [])
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    @Test("`false` is not treated as a lost field")
    func falseIsNotEmpty() {
        let issues = analyze("""
        final class OrderStore {
            func save(_ order: Order) {
                record.setValue(order.identifier, forKey: "identifier")
            }

            func load() -> Order {
                Order(identifier: record.value(forKey: "identifier"), isGift: false)
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    @Test("test files are not analysed")
    func testFilesAreSilent() {
        let issues = analyze("""
        final class OrderStore {
            func save(_ order: Order) {
                record.setValue(order.identifier, forKey: "identifier")
            }

            func load() -> Order {
                Order(identifier: record.value(forKey: "identifier"), items: [])
            }
        }
        """, filePath: "Tests/CheckoutTests/StoreTests.swift")

        #expect(issues.isEmpty)
    }
}

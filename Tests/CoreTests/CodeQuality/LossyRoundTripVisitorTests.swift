@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A type that takes a value apart into storage and rebuilds it with a field hard-coded empty — so
/// the field never survives the round trip.
///
/// The motivating bug is the Checkout sample's Core Data store: `save(_:)` wrote three fields and
/// `recentOrders()` rebuilt every order with `items: []` and `discount: nil`. It compiled, satisfied
/// the store protocol, and passed every test that used an in-memory double. Only a save-then-fetch
/// property test, run against the real store, caught it.
///
/// What it must not report is in `LossyRoundTripFalsePositiveTests`.
@Suite("Lossy round trip")
struct LossyRoundTripVisitorTests {

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

    // MARK: - The shape it exists for

    /// The Checkout sample's store on `main`, verbatim in the parts that matter.
    @Test("a Core Data store that never persists two fields fires at the rebuild")
    func coreDataStoreFires() throws {
        let issues = analyze("""
        actor CoreDataOrderStore: OrderStore {
            func save(_ order: Order) async throws {
                let context = container.newBackgroundContext()
                try await context.perform {
                    let record = NSEntityDescription.insertNewObject(forEntityName: "OrderRecord", into: context)
                    record.setValue(order.identifier, forKey: "identifier")
                    record.setValue(order.total.cents, forKey: "totalCents")
                    record.setValue(order.paymentMethod.rawValue, forKey: "paymentMethod")
                    try context.save()
                }
            }

            func recentOrders() async throws -> [Order] {
                let context = container.newBackgroundContext()
                return try await context.perform {
                    let request = NSFetchRequest<NSManagedObject>(entityName: "OrderRecord")
                    return try context.fetch(request).compactMap { record in
                        guard
                            let identifier = record.value(forKey: "identifier") as? UUID,
                            let methodName = record.value(forKey: "paymentMethod") as? String,
                            let method = PaymentMethod(rawValue: methodName)
                        else { return nil }
                        return Order(identifier: identifier, items: [], paymentMethod: method, discount: nil)
                    }
                }
            }
        }
        """)

        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.lineNumber == 23)
        #expect(issue.message.contains("`save(_:)` never stores `items` or `discount`"))
        #expect(issue.message.contains("`recentOrders()` rebuilds it with `items: []`, `discount: nil`"))
    }

    /// The stronger claim: the field was written, and the load threw it away.
    @Test("a field stored and then discarded on load is reported as thrown away")
    func storedThenDiscardedFires() throws {
        let issue = try #require(analyze("""
        final class OrderDefaults {
            func save(_ order: Order) {
                defaults.set(order.identifier.uuidString, forKey: "identifier")
                defaults.set(order.discount?.value, forKey: "discount")
            }

            func load() -> Order? {
                guard let raw = defaults.string(forKey: "identifier"), let identifier = UUID(uuidString: raw) else {
                    return nil
                }
                return Order(identifier: identifier, discount: nil)
            }
        }
        """).first)

        #expect(issue.message.contains("`save(_:)` stores `discount`, but `load()` throws it away: `discount: nil`"))
    }

    /// The same bug in an edit form: the initialiser copies an existing value into properties, and the
    /// save path rebuilds it from them — without the field the initialiser never copied. Saving an
    /// edit wipes that field. Found in a sibling repo while measuring this rule.
    @Test("an edit form that rebuilds the value without a field fires")
    func editFormRoundTripFires() throws {
        let issue = try #require(analyze("""
        @Observable
        final class SkillComposeViewModel {
            var identifier = ""
            var name = ""

            init(editing: SkillDraft? = nil) {
                self.isEditing = (editing != nil)
                guard let editing else { return }
                identifier = editing.identifier
                name = editing.name
            }

            private func buildDraft() -> SkillDraft {
                SkillDraft(identifier: identifier, name: name.trimmed, tags: [])
            }
        }
        """).first)

        #expect(issue.message.contains("`init(editing:)` never stores `tags`"))
    }

    /// A record type mapping to and from the domain — SwiftData's `@Model`, a DTO, a GRDB row.
    @Test("a record type whose toDomain drops a field fires")
    func recordMappingFires() {
        let issues = analyze("""
        @Model
        final class OrderEntity {
            var identifier: UUID
            var method: String

            init(order: Order) {
                identifier = order.identifier
                method = order.paymentMethod.rawValue
            }

            var domain: Order {
                Order(identifier: identifier, items: [], paymentMethod: PaymentMethod(rawValue: method))
            }
        }
        """)

        #expect(issues.count == 1)
    }

    @Test("the two halves in a same-file extension still pair")
    func sameFileExtensionPairs() {
        let issues = analyze("""
        struct OrderArchive {
            func save(_ order: Order) {
                store.set(order.identifier, forKey: Keys.identifier)
            }
        }

        extension OrderArchive {
            func load() -> Order {
                Order(identifier: store.uuid(forKey: Keys.identifier), items: [])
            }
        }
        """)

        #expect(issues.count == 1)
    }

    @Test("an array parameter decomposed in a loop is a decomposition")
    func arrayParameterLoopFires() {
        let issues = analyze("""
        final class OrderStore {
            func save(_ orders: [Order]) {
                for order in orders {
                    record.setValue(order.identifier, forKey: "identifier")
                }
            }

            func fetch() -> [Order] {
                records.map { Order(identifier: $0.value(forKey: "identifier"), items: []) }
            }
        }
        """)

        #expect(issues.count == 1)
    }

    /// The fixed Checkout store encodes `items` into a local first. The local carries the field to the
    /// key it is stored under, so a load that then drops it is "thrown away", not "never stored".
    @Test("a field stored through a local alias counts as stored")
    func aliasCarriesField() throws {
        let issue = try #require(analyze("""
        final class OrderStore {
            func save(_ order: Order) throws {
                let encodedItems = try JSONEncoder().encode(order.items)
                record.setValue(order.identifier, forKey: "identifier")
                record.setValue(encodedItems, forKey: "lineItems")
            }

            func load() -> Order {
                Order(identifier: record.value(forKey: "identifier"), items: [])
            }
        }
        """).first)

        #expect(issue.message.contains("stores `items`, but `load()` throws it away"))
    }
}

@testable import Core
import SwiftParser
import SwiftSyntax
import Testing

@Suite
struct IdentifiableCollectionPropertyCatalogTests {

    private func catalog(_ sources: [String], identifiable: Set<String>) -> Set<String> {
        IdentifiableCollectionPropertyCatalog.build(
            from: sources.map { Parser.parse(source: $0) }, identifiable: identifiable
        )
    }

    @Test func listsAnArrayPropertyOfAnIdentifiableType() {
        let names = catalog(
            ["final class Model { var insights: [Insight] = []; var history: Array<Entry> = [] }"],
            identifiable: ["Insight", "Entry"]
        )
        #expect(names == ["insights", "history"])
    }

    @Test func leavesOutAnArrayOfANonIdentifiableType() {
        let names = catalog(["struct Model { var names: [String] }"], identifiable: ["Insight"])
        #expect(names.isEmpty)
    }

    /// Matching is by name, so one declaration that is not an Identifiable array keeps it out.
    @Test func leavesOutANameAnyDeclarationDisagreesWith() {
        let names = catalog(
            [
                "final class Model { var history: [Entry] = [] }",
                "struct Log { var history: [String] }",
                "struct Cache { var insights = [Insight]() }"
            ],
            identifiable: ["Entry", "Insight"]
        )
        #expect(names.isEmpty)
    }

    /// A local in some function body is not the property a view reads through `model.items`.
    @Test func ignoresLocalVariables() {
        let names = catalog(
            [
                "final class Model { var items: [Item] = [] }",
                "func build() { let items: [String] = [] }"
            ],
            identifiable: ["Item"]
        )
        #expect(names == ["items"])
    }
}

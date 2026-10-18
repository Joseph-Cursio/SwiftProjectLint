@testable import Core
import SwiftParser
import SwiftSyntax
import Testing

@Suite
struct IdentifiableTypeCollectorTests {

    private func collect(from source: String) -> Set<String> {
        let syntax = Parser.parse(source: source)
        let collector = IdentifiableTypeCollector()
        collector.walk(syntax)
        return collector.collectedTypes
    }

    @Test func testCollectsIdentifiableStruct() {
        let source = """
        struct Item: Identifiable {
            let id: UUID
            let name: String
        }
        """
        let types = collect(from: source)
        #expect(types == ["Item"])
    }

    @Test func testCollectsIdentifiableEnum() {
        let source = """
        enum Severity: String, CaseIterable, Identifiable {
            case warning, error
            var id: String { rawValue }
        }
        """
        let types = collect(from: source)
        #expect(types == ["Severity"])
    }

    @Test func testCollectsIdentifiableClass() {
        let source = """
        class Document: Identifiable {
            let id = UUID()
        }
        """
        let types = collect(from: source)
        #expect(types == ["Document"])
    }

    @Test func testIgnoresNonIdentifiableTypes() {
        let source = """
        struct PlainStruct: Codable, Sendable {
            let name: String
        }
        enum PlainEnum: String {
            case one
        }
        """
        let types = collect(from: source)
        #expect(types.isEmpty)
    }

    @Test func testCollectsMultipleIdentifiableTypes() {
        let source = """
        struct ItemA: Identifiable {
            let id: UUID
        }
        struct ItemB: Codable {
            let name: String
        }
        enum Status: String, Identifiable {
            case active
            var id: String { rawValue }
        }
        """
        let types = collect(from: source)
        #expect(types == ["ItemA", "Status"])
    }
    /// SwiftData's `@Model` makes a class a `PersistentModel`, which refines `Identifiable`.
    @Test func testCollectsSwiftDataModelClass() {
        let source = """
        @Model
        final class DiagramEntity {
            var name: String = ""
        }
        """
        #expect(collect(from: source) == ["DiagramEntity"])
    }

    @Test func testCollectsConformanceDeclaredInAnExtension() {
        let source = """
        struct Item {
            let id: UUID
        }
        extension Item: Identifiable {}
        """
        #expect(collect(from: source) == ["Item"])
    }

    /// `@retroactive` wraps the conformance in an attributed type; it is still `Identifiable`.
    @Test func testCollectsRetroactiveConformanceInAnExtension() {
        let source = """
        extension Tag: @retroactive Identifiable {}
        extension Version: @retroactive Swift.Identifiable {}
        """
        #expect(collect(from: source) == ["Tag", "Version"])
    }

    /// A nested type is listed under its leaf and every qualified spelling of it, whether the
    /// conformance is declared in place, inside an extension of the outer type, or on a
    /// qualified extension.
    @Test func testCollectsNestedTypesUnderTheirQualifiedPaths() {
        let source = """
        enum Feed { struct Entry { let id: UUID } }
        extension Feed.Entry: Identifiable {}
        struct Outer { enum Middle { class Inner: Identifiable { let id = 0 } } }
        extension Store { struct Row: Identifiable { let id: Int } }
        """
        #expect(collect(from: source) == [
            "Entry", "Feed.Entry",
            "Inner", "Middle.Inner", "Outer.Middle.Inner",
            "Row", "Store.Row"
        ])
    }

    /// A type local to a function is not reachable through its enclosing type's name.
    @Test func testLocalTypeIsListedByItsOwnNameOnly() {
        let source = """
        struct Screen { func rows() { struct Row: Identifiable { let id: Int } } }
        """
        #expect(collect(from: source) == ["Row"])
    }

    @Test func testIgnoresOtherAttributesAndExtensions() {
        let source = """
        @Observable
        final class Store {}
        extension Store: Equatable {}
        """
        #expect(collect(from: source).isEmpty)
    }
}

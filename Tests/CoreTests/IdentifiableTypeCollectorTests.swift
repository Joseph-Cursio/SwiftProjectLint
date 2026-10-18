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

    @Test func testIgnoresOtherAttributesAndExtensions() {
        let source = """
        @Observable
        final class Store {}
        extension Store: Equatable {}
        """
        #expect(collect(from: source).isEmpty)
    }
}

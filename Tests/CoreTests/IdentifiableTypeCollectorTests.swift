import Testing
import SwiftSyntax
import SwiftParser
@testable import Core

@Suite
struct IdentifiableTypeCollectorTests {

    private func collect(from source: String) -> Set<String> {
        let syntax = Parser.parse(source: source)
        let collector = IdentifiableTypeCollector()
        collector.walk(syntax)
        return collector.identifiableTypes
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
}

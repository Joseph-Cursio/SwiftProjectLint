@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

@Suite
struct EquatableConformanceCollectorTests {

    private func collect(from source: String) -> Set<String> {
        let syntax = Parser.parse(source: source)
        let collector = EquatableConformanceCollector()
        collector.walk(syntax)
        return collector.collectedTypes
    }

    @Test func collectsInlineEquatableStruct() {
        #expect(collect(from: "struct Point: Equatable { var x: Int }") == ["Point"])
    }

    @Test func collectsHashableAndComparableAsEquatable() {
        let source = """
        struct A: Hashable { var x: Int }
        struct B: Comparable { var y: Int }
        """
        #expect(collect(from: source) == ["A", "B"])
    }

    @Test func collectsEnumAndClassConformers() {
        let source = """
        enum E: Equatable { case a }
        final class C: Equatable { static func == (l: C, r: C) -> Bool { true } }
        """
        #expect(collect(from: source) == ["E", "C"])
    }

    @Test func collectsConformanceAddedViaExtension() {
        let source = """
        struct Theme { var accent: Int }
        extension Theme: Equatable {}
        """
        #expect(collect(from: source) == ["Theme"])
    }

    @Test func ignoresNonEquatableConformances() {
        let source = """
        struct Plain { var x: Int }
        struct Coded: Codable { var y: Int }
        protocol P: Sendable {}
        """
        #expect(collect(from: source).isEmpty)
    }

    @Test func collectsTypeWithMixedConformances() {
        #expect(collect(from: "struct M: Codable, Equatable, Sendable { var x: Int }") == ["M"])
    }
}

@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Shared driver for the two suites below, at file scope so both can reach it.
enum TestSupport {

static func analyze(
    _ source: String,
    filePath: String = "Logic.swift",
    equatableTypes: Set<String> = [],
    valueTypes: Set<String> = []
) -> [LintIssue] {
    let visitor = PureFunctionCandidateVisitor(patternCategory: .testability)
    visitor.knownEquatableTypes = equatableTypes
    visitor.knownValueTypes = valueTypes
    let syntax = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
    visitor.setSourceLocationConverter(converter)
    visitor.setFilePath(filePath)
    visitor.walk(syntax)
    return visitor.detectedIssues.filter { $0.ruleName == .pureFunctionCandidate }
}
}

@Suite
struct PureFunctionCandidateVisitorTests {

    func analyze(
        _ source: String,
        filePath: String = "Logic.swift",
        equatableTypes: Set<String> = [],
        valueTypes: Set<String> = []
    ) -> [LintIssue] {
        TestSupport.analyze(
            source,
            filePath: filePath,
            equatableTypes: equatableTypes,
            valueTypes: valueTypes
        )
    }

    @Test func flagsFreePureFunction() throws {
        let issue = try #require(analyze("func add(_ a: Int, _ b: Int) -> Int { a + b }").first)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("add"))
    }

    @Test func flagsStaticPureFunction() {
        let source = """
        enum Math {
            static func square(_ x: Int) -> Int { x * x }
        }
        """
        #expect(analyze(source).count == 1)
    }

    @Test("B26 — a `Self`-returning value-semantic method is a candidate (Self resolves to its type)")
    func flagsSelfReturningMethod() {
        // `union(_ other: Self) -> Self` — the idiomatic SetAlgebra shape. The
        // `Self` return resolves to the enclosing (Equatable) `Ring`, so it is
        // assertable rather than dropped for an unrecognized `"Self"` base name.
        let source = """
        struct Ring {
            let items: [Int]
            func union(_ other: Self) -> Self { Ring(items: items + other.items) }
        }
        """
        #expect(analyze(source, equatableTypes: ["Ring"]).count == 1)
    }

    @Test("a `Self` return whose enclosing type is NOT Equatable is still not a candidate")
    func selfReturnRequiresEquatableEnclosingType() {
        let source = """
        struct Ring {
            let items: [Int]
            func union(_ other: Self) -> Self { Ring(items: items + other.items) }
        }
        """
        #expect(analyze(source, equatableTypes: []).isEmpty)
    }

    // MARK: - Bare `self` as a value (B26 — the OrderedSet.union slice)

    @Test("B26 — a value type copying bare `self` and mutating the copy is a candidate")
    func flagsValueTypeBareSelfCopyMutate() {
        // The idiomatic value-semantic `union`: copy `self`, mutate the copy via a
        // `mutating` primitive, return it. `self` IS the value, so this is a
        // function of `(self, other)`. The inline `struct` is seen directly, so no
        // cross-file value-type index is needed here.
        let source = """
        struct Bag: Equatable {
            var items: [Int]
            mutating func formUnion(_ other: Bag) { items += other.items }
            func union(_ other: Bag) -> Bag {
                var result = self
                result.formUnion(other)
                return result
            }
        }
        """
        let unions = analyze(source, equatableTypes: ["Bag"]).filter { $0.message.contains("union") }
        #expect(unions.count == 1)
    }

    @Test("B26 — bare `self` in an extension seeds when the extended type is a known value type")
    func flagsBareSelfInExtensionOfValueType() {
        // The real OrderedSet shape: `union` lives in `extension OrderedSet`, whose
        // syntax never says `struct`. The cross-file value-type index supplies the
        // kind — mirroring `ValueTypeCollector` in a full run.
        let source = """
        extension Bag {
            func union(_ other: Bag) -> Bag {
                var result = self
                result.formUnion(other)
                return result
            }
        }
        """
        #expect(analyze(source, equatableTypes: ["Bag"], valueTypes: ["Bag"]).count == 1)
    }

    @Test("bare `self` in an extension is NOT a candidate when the type's kind is unknown")
    func bareSelfInExtensionRequiresKnownValueType() {
        // Without the value-type index, the extended type might be a class — whose
        // copy aliases a shared object — so the safe direction is to drop it.
        let source = """
        extension Bag {
            func union(_ other: Bag) -> Bag {
                var result = self
                result.formUnion(other)
                return result
            }
        }
        """
        #expect(analyze(source, equatableTypes: ["Bag"], valueTypes: []).isEmpty)
    }

    @Test("a reference type copying bare `self` stays out — the copy aliases a shared object")
    func referenceTypeBareSelfStaysRejected() {
        let source = """
        final class Box: Equatable {
            let items: [Int]
            init(_ items: [Int]) { self.items = items }
            static func == (lhs: Box, rhs: Box) -> Bool { lhs.items == rhs.items }
            func duplicate(_ other: Box) -> Box {
                let result = self
                return result
            }
        }
        """
        let dupes = analyze(source, equatableTypes: ["Box"], valueTypes: [])
            .filter { $0.message.contains("duplicate") }
        #expect(dupes.isEmpty)
    }

    // MARK: - Not candidates

    @Test func ignoresVoidReturn() {
        #expect(analyze("func log(_ x: Int) { }").isEmpty)
    }

    @Test func ignoresNoParameters() {
        #expect(analyze("func make() -> Int { 42 }").isEmpty)
    }

    @Test func ignoresAsync() {
        #expect(analyze("func load(_ id: Int) async -> Int { id }").isEmpty)
    }

    @Test func ignoresImpureBody() {
        // print is an impurity marker.
        #expect(analyze("func add(_ a: Int, _ b: Int) -> Int { print(a); return a + b }").isEmpty)
    }

    @Test func ignoresRandomness() {
        #expect(analyze("func roll(_ n: Int) -> Int { Int.random(in: 0...n) }").isEmpty)
    }
}

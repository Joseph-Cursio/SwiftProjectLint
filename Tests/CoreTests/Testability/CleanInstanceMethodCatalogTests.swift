@testable import Core
import Foundation
import SwiftParser
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Covers the sibling-call gate: an instance method that *calls* another method used to be refused
/// outright, which held it to a stricter standard than a free function doing the same thing.
@Suite
struct CleanInstanceMethodCatalogTests {

    private func catalog(_ sources: String...) -> CleanInstanceMethodCatalog {
        CleanInstanceMethodCatalog.build(from: sources.map { Parser.parse(source: $0) })
    }

    private func clean(_ sources: String...) -> Set<String> {
        CleanInstanceMethodCatalog
            .build(from: sources.map { Parser.parse(source: $0) })
            .cleanMethods(on: "Engine")
    }

    // MARK: - Membership

    @Test func clearsAMethodThatIsAFunctionOfItsInputs() {
        #expect(clean("""
        struct Engine {
            func format(_ text: String) -> String { text + "!" }
        }
        """) == ["format"])
    }

    @Test func clearsAChainToAFixpointRegardlessOfDeclarationOrder() {
        // `outer` is declared before the callee it depends on, so a single ordered pass would
        // miss it. Both must come out clean.
        #expect(clean("""
        struct Engine {
            func outer(_ text: String) -> String { middle(text) }
            func middle(_ text: String) -> String { inner(text) }
            func inner(_ text: String) -> String { text + "!" }
        }
        """) == ["outer", "middle", "inner"])
    }

    @Test func resolvesAcrossFilesAndExtensions() {
        // The case that motivated the catalog: `serialize` and its callee live in different files.
        let names = clean(
            "struct Engine { let separator: String }",
            "extension Engine { func serialize(_ text: String) -> String { decorate(text) } }",
            "extension Engine { func decorate(_ text: String) -> String { text + \"!\" } }"
        )
        #expect(names == ["serialize", "decorate"])
    }

    // MARK: - Refusals

    @Test func refusesAMethodReadingMutableState() {
        #expect(clean("""
        struct Engine {
            var count: Int = 0
            func tally(_ step: Int) -> Int { count + step }
        }
        """).isEmpty)
    }

    @Test func refusalPropagatesToItsCallers() {
        // The caller is only as good as what it calls — this is what keeps the relaxation from
        // laundering mutable state through one level of indirection.
        #expect(clean("""
        struct Engine {
            var count: Int = 0
            func outer(_ step: Int) -> Int { tally(step) }
            func tally(_ step: Int) -> Int { count + step }
        }
        """).isEmpty)
    }

    @Test func refusesAMutatingMethodAndAnyNameItOverloads() {
        // A call site names a method, not a signature, so one mutating overload disqualifies the
        // name for every other.
        #expect(clean("""
        struct Engine {
            var count: Int = 0
            func bump(_ step: Int) -> Int { step }
            mutating func bump(_ step: String) -> Int { count += 1; return count }
        }
        """).isEmpty)
    }

    @Test func refusesAnImpureMethod() {
        #expect(clean("""
        struct Engine {
            func stamp(_ text: String) -> String { text + Date().description }
        }
        """).isEmpty)
    }

    @Test func neverPromotesACycle() {
        // Mutual recursion has no base case to promote from; the fixpoint must terminate with both
        // out rather than spinning.
        #expect(clean("""
        struct Engine {
            func ping(_ text: String) -> String { pong(text) }
            func pong(_ text: String) -> String { ping(text) }
        }
        """).isEmpty)
    }

    @Test func refusesEverythingOnAnActor() {
        #expect(clean("""
        actor Engine {
            func format(_ text: String) -> String { text + "!" }
        }
        """).isEmpty)
    }

    @Test func keepsTypesApart() {
        let built = catalog("""
        struct Engine { func format(_ text: String) -> String { text } }
        struct Other { var count = 0; func format(_ text: String) -> String { text } }
        """)
        #expect(built.cleanMethods(on: "Engine") == ["format"])
        #expect(built.cleanMethods(on: "Other") == ["format"])
        #expect(built.cleanMethods(on: "Missing").isEmpty)
        #expect(built.cleanMethods(on: nil).isEmpty)
    }

    @Test func emptyCatalogClearsNothing() {
        #expect(CleanInstanceMethodCatalog.empty.isEmpty)
        #expect(CleanInstanceMethodCatalog.empty.cleanMethods(on: "Engine").isEmpty)
    }
}

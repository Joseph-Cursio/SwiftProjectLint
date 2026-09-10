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

    /// **This test used to assert the opposite, and the comment above it said why: "mutual
    /// recursion has no base case to promote from; the fixpoint must terminate with both out."**
    /// The second half of that sentence was a fact about the loop's direction written up as a
    /// requirement. Both of these are functions of their argument — the only thing either does is
    /// hand `text` to the other — and refusing them cost their whole enclosing type its kernel
    /// status, which is how three `Concrete Type Usage` findings came to ask for a protocol seam
    /// in front of a parser (SwiftProjectLint#195).
    ///
    /// What the old test was right about is termination, and that is still pinned: this returns.
    @Test func aPureCycleIsClean() {
        #expect(clean("""
        struct Engine {
            func ping(_ text: String) -> String { pong(text) }
            func pong(_ text: String) -> String { ping(text) }
        }
        """) == ["ping", "pong"])
    }

    /// The direction that makes the optimistic start safe. One member is refuted on evidence that
    /// owes nothing to the assumption — the purity oracle sees the clock — and the other follows
    /// on the next pass because its only unresolved reference is to a name no longer believed
    /// clean. Assume-then-refute reaches the same answer as the old loop wherever the old loop had
    /// an answer.
    @Test func aCycleWithAnImpureMemberIsNotClean() {
        #expect(clean("""
        struct Engine {
            func ping(_ text: String) -> String { pong(text) }
            func pong(_ text: String) -> String { ping(text + Date().description) }
        }
        """).isEmpty)
    }

    /// A self-call under one name, which is what overload groups produce: the catalog keys methods
    /// by name, so a two-argument form delegating to a four-argument one is a name that calls
    /// itself. This is the exact shape of `EffectAnnotationParser.combinedDocTrivia`.
    @Test func anOverloadDelegatingToItsSiblingIsClean() {
        #expect(clean("""
        struct Engine {
            func render(_ text: String) -> String { render(text, width: 80) }
            func render(_ text: String, width: Int) -> String { String(text.prefix(width)) }
        }
        """) == ["render"])
    }

    /// A cycle where one member reads mutable storage. Storage access is judged without reference
    /// to the assumed set, so this demotes on the first pass whatever the loop believes about
    /// sibling calls.
    @Test func aCycleReadingMutableStateIsNotClean() {
        #expect(clean("""
        struct Engine {
            var count: Int = 0
            func ping(_ text: String) -> String { pong(text) }
            func pong(_ text: String) -> String { text + String(count) }
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

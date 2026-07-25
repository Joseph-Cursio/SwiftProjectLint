import PropertyBased
import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Property-based law: **`CleanInstanceMethodCatalog.build` does not depend on
/// file order.**
///
/// This is not an invented property. It is the claim the type's own
/// documentation makes, in prose, as the justification for the fixpoint loop:
///
/// > *"The loop is what lets `serialize` qualify on the pass after
/// > `orderedTopLevelPairs` did, so declaration order — and file order — does
/// > not decide the answer."*
///
/// A sentence like that is a reference definition, and a reference definition is
/// a property. Without the loop, a single resolution pass promotes a method only
/// if its callees happen to have been promoted already — which is decided by the
/// order `[SourceFileSyntax]` arrives in, which is decided by directory
/// enumeration. The bug that removing the loop introduces is therefore
/// **invisible to any fixed-fixture test**: every fixture has one file order, and
/// whichever answer that order produces is the one the fixture's expectations get
/// written against.
///
/// The catalog gates whether an instance method is a property-test candidate at
/// all, so an order-dependent answer means the *set of functions this linter
/// recommends testing* varies with how the file system enumerates a directory.
///
/// ## Why the chain is generated rather than fixed
///
/// The fixpoint only earns its keep when a method's callee is promoted on a
/// *later* pass than the method is first considered. That needs a call chain
/// longer than one hop, split across files, in an unhelpful order. Generating
/// both the chain length and the permutation covers the orderings a hand-written
/// fixture would never think to write down — including the worst case, where the
/// files arrive in exactly reverse dependency order.
@Suite
struct CleanMethodCatalogOrderIndependenceTests {

    // MARK: - Fixture construction

    /// The type every generated fragment extends. `base` is a `let`, so reading
    /// it keeps a method clean; `counter` is a `var`, so reading it does not.
    private static let primaryDeclaration = """
    struct Widget {
        let base: Int
        var counter: Int
    }
    """

    /// Link *i* of a clean call chain: `step0` calls `step1` calls `step2` … and
    /// the last link bottoms out on the immutable stored property.
    ///
    /// Each link lives in its own file, mirroring the real motivating case
    /// (`…+Serialization.swift` calling into `…+Comments.swift`).
    private static func cleanLink(_ index: Int, of length: Int) -> String {
        let body = index == length - 1 ? "base" : "step\(index + 1)(x)"
        return """
        extension Widget {
            func step\(index)(_ x: Int) -> Int { \(body) + x }
        }
        """
    }

    /// A method that reads mutable instance state, plus a caller of it. Neither
    /// may ever be promoted — cleanliness has to propagate refusal as well as
    /// admission, or the gate leaks.
    private static let dirtyLink = """
    extension Widget {
        func readsMutable() -> Int { counter }
        func callsDirty(_ x: Int) -> Int { readsMutable() + x }
    }
    """

    private static func parse(_ sources: [String]) -> [SourceFileSyntax] {
        sources.map { Parser.parse(source: $0) }
    }

    // MARK: - Laws

    /// **L1.1 — file-order independence.** Building from the same files in any
    /// order yields an identical catalog.
    ///
    /// `CleanInstanceMethodCatalog` is `Equatable`, so this compares the whole
    /// catalog, not a projection of it.
    @Test
    func catalogIsIndependentOfFileOrder() async {
        await propertyCheck(input: Gen<Int>.int(in: 1...6), Gen<Int>.int(in: 0...64)) { length, seed in
            var files = [Self.primaryDeclaration, Self.dirtyLink]
            files.append(contentsOf: (0..<length).map { Self.cleanLink($0, of: length) })

            // A deterministic rotation-plus-reversal keyed on the generated seed:
            // cheap, and it reliably includes exact reverse dependency order,
            // which is the arrangement a single-pass resolver fails on.
            var permuted = Array(files[(seed % files.count)...] + files[..<(seed % files.count)])
            if seed.isMultiple(of: 2) { permuted.reverse() }

            let reference = CleanInstanceMethodCatalog.build(from: Self.parse(files))
            let permutedCatalog = CleanInstanceMethodCatalog.build(from: Self.parse(permuted))

            #expect(
                reference == permutedCatalog,
                """
                Catalog changed under a file-order permutation (chain length \
                \(length), seed \(seed)). The fixpoint in `resolve` exists \
                precisely to make this impossible.
                """
            )
        }
    }

    /// The concrete claim the doc comment makes, pinned: **the whole chain
    /// resolves even when the files arrive in exactly the wrong order.**
    ///
    /// Order-independence alone is satisfiable by a broken resolver that
    /// promotes *nothing* in every order. This law is the other half — it fixes
    /// what the answer has to be, so the law above cannot be passed vacuously.
    @Test
    func fullChainResolvesInReverseDependencyOrder() async {
        await propertyCheck(input: Gen<Int>.int(in: 1...6)) { length in
            let links = (0..<length).map { Self.cleanLink($0, of: length) }
            // Reversed: `step0`, which depends on everything, is seen first.
            let files = [Self.primaryDeclaration] + links.reversed()

            let catalog = CleanInstanceMethodCatalog.build(from: Self.parse(files))
            let clean = catalog.cleanMethods(on: "Widget")

            for index in 0..<length {
                #expect(
                    clean.contains("step\(index)"),
                    "step\(index) was not promoted at chain length \(length) — the fixpoint stopped early"
                )
            }
        }
    }

    /// Refusal propagates: a method reading a `var`, and anything that calls it,
    /// stay out of the catalog in every order.
    ///
    /// This is the soundness direction. The catalog's whole safety argument is
    /// that *membership is earned* — if refusal failed to propagate, a caller of
    /// a state-reading method would be judged a function of its inputs when it
    /// is not.
    @Test
    func refusalPropagatesRegardlessOfOrder() async {
        await propertyCheck(input: Gen<Int>.int(in: 0...8)) { rotation in
            let files = [Self.primaryDeclaration, Self.dirtyLink, Self.cleanLink(0, of: 1)]
            let offset = rotation % files.count
            let permuted = Array(files[offset...] + files[..<offset])

            let clean = CleanInstanceMethodCatalog.build(from: Self.parse(permuted))
                .cleanMethods(on: "Widget")

            #expect(clean.contains("readsMutable") == false, "a method reading a `var` was promoted")
            #expect(clean.contains("callsDirty") == false, "a caller of a state-reading method was promoted")
            // The clean link is unaffected by the dirty one's presence.
            #expect(clean.contains("step0"))
        }
    }

    /// **L1.3 — no sources, no catalog.** The pre-scan-free caller must get the
    /// pre-catalog behaviour: nothing clean, so every callee stays refused.
    @Test
    func buildingFromNoSourcesYieldsTheEmptyCatalog() {
        let catalog = CleanInstanceMethodCatalog.build(from: [])
        #expect(catalog.isEmpty)
        #expect(catalog == .empty)
        #expect(catalog.cleanMethods(on: "Widget").isEmpty)
    }

    /// A free function has no enclosing type, and the catalog is keyed by type,
    /// so `nil` must answer "nothing" rather than trapping or matching a stray
    /// entry.
    @Test
    func freeFunctionsHaveNoCleanMethods() {
        let catalog = CleanInstanceMethodCatalog.build(
            from: Self.parse([Self.primaryDeclaration, Self.cleanLink(0, of: 1)])
        )
        #expect(catalog.cleanMethods(on: nil).isEmpty)
        #expect(catalog.cleanMethods(on: "NoSuchType").isEmpty)
    }

    /// **L1.5 — actors are excluded.** `resolve` skips actor-declared types, and
    /// it must keep doing so: an actor's method is isolated state access, not a
    /// function of its inputs, whatever its body reads.
    @Test
    func actorMethodsAreNeverPromoted() {
        let source = """
        actor Counter {
            let base: Int
            func pure(_ x: Int) -> Int { base + x }
        }
        """
        let catalog = CleanInstanceMethodCatalog.build(from: Self.parse([source]))
        #expect(catalog.cleanMethods(on: "Counter").isEmpty)
    }

    /// **Overloads are all-or-nothing.** A call site names a method, not a
    /// signature, so one dirty overload must disqualify the name entirely.
    ///
    /// This is stated in the type's documentation and is the kind of rule that
    /// decays quietly: the natural implementation — judge each declaration and
    /// promote the ones that pass — is wrong, and wrong in the unsound
    /// direction.
    @Test
    func oneDirtyOverloadDisqualifiesTheWholeName() {
        let source = """
        extension Widget {
            func value(_ x: Int) -> Int { base + x }
            func value(_ x: String) -> Int { counter }
        }
        """
        let catalog = CleanInstanceMethodCatalog.build(
            from: Self.parse([Self.primaryDeclaration, source])
        )
        #expect(
            catalog.cleanMethods(on: "Widget").contains("value") == false,
            "`value` was promoted despite an overload that reads mutable state"
        )
    }
}

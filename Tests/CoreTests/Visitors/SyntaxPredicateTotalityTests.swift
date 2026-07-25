import PropertyBased
import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Totality and refinement laws for the SwiftSyntax predicates in `SyntaxHelpers`.
///
/// ## Where this came from
///
/// These are written to the recipe `swift-infer discover` now emits for a
/// parser-constructed carrier. The tool proposed the `predicate` law on each of
/// these functions and used to print `Generator: not derived (no strategy
/// matched this type)` — which reads as *this law cannot be run*. For a
/// SwiftSyntax node that is simply false: nodes are parsed, not built, so you
/// generate the **source** and run the law over the tree.
///
/// This file is that recipe, pasted and filled in. It exists partly to hold the
/// predicates to their contract and partly as the check that the emitted recipe
/// is genuinely runnable — a recipe that does not compile is advice, not a
/// generator.
///
/// ## Why parse rather than construct
///
/// SwiftSyntax nodes *can* be built programmatically, and doing so here would be
/// a mistake: hand-assembled trees have arrangements and trivia the parser never
/// produces, so a law checked against them is answering about inputs that cannot
/// occur. Parsing is the correct domain restriction, not a workaround.
@Suite
struct SyntaxPredicateTotalityTests {

    /// Finds every node of a type in a parsed tree.
    ///
    /// The one helper the recipe asks a test target to paste once.
    private static func descendants<T: SyntaxProtocol>(
        of type: T.Type,
        in node: some SyntaxProtocol
    ) -> [T] {
        node.children(viewMode: .sourceAccurate).flatMap { child -> [T] in
            (child.as(T.self).map { [$0] } ?? []) + descendants(of: type, in: child)
        }
    }

    /// A small, deliberately awkward corpus.
    ///
    /// Most fragments produce nodes the predicates can be both true and false
    /// about. The last three are malformed on purpose: totality is the law under
    /// test, and half-written code is exactly what an analyser is handed on every
    /// keystroke — the case a fixture of well-formed snippets never covers.
    private static let sourceGen = Gen<String?>.element(of: [
        "struct S { var x = 0 }",
        "struct V: View { var body: some View { Text(\"hi\") } }",
        "struct A: App { var body: some Scene { WindowGroup { } } }",
        "struct Both: View, Identifiable { var id = 0; var body: some View { EmptyView() } }",
        "final class C { func f(_ x: Int) -> Int { x } }",
        "enum E { case a, b }",
        "extension S { var doubled: Int { x * 2 } }",
        "let rows = ForEach(items) { item in Text(item.name) }",
        "let ids = ForEach(Suit.allCases, id: \\.self) { s in Text(s.rawValue) }",
        "let indexed = ForEach(0..<10) { index in Text(\"\\(index)\") }",
        // Malformed on purpose.
        "struct Half { var x =",
        "func broken( {",
        ""
    ] as [String]).map { $0 ?? "" }

    /// **Totality.** `isSwiftUIView` answers for every struct the parser can
    /// produce, including from malformed source — it never traps.
    ///
    /// The law a predicate owes by virtue of being one. It looks trivial and is
    /// not: these walk optional chains through `inheritanceClause`, and a
    /// half-parsed declaration is where those go missing.
    @Test
    func viewPredicatesAreTotalOverEveryParsedStruct() async {
        await propertyCheck(input: Self.sourceGen) { source in
            let tree = Parser.parse(source: source)
            for node in Self.descendants(of: StructDeclSyntax.self, in: tree) {
                // Reaching here without trapping is the law.
                _ = isSwiftUIView(node)
                _ = isSwiftUIViewOnly(node)
            }
        }
    }

    /// **`isSwiftUIViewOnly` refines `isSwiftUIView`.** Anything that is a
    /// View-only is also a View.
    ///
    /// A relationship between two predicates that no single-predicate law can
    /// see, and the kind that decays quietly: the two read the same inheritance
    /// clause against different protocol sets, so a change to one set that
    /// forgets the other inverts the containment without failing anything else.
    @Test
    func viewOnlyImpliesView() async {
        await propertyCheck(input: Self.sourceGen) { source in
            let tree = Parser.parse(source: source)
            for node in Self.descendants(of: StructDeclSyntax.self, in: tree)
            where isSwiftUIViewOnly(node) {
                #expect(isSwiftUIView(node), "a View-only struct was not recognised as a View")
            }
        }
    }

    /// A struct conforming to `App` is a SwiftUI type but not a View-only one —
    /// the boundary the two predicates exist to draw, pinned so the sets cannot
    /// silently merge.
    @Test
    func appConformanceIsAViewButNotViewOnly() throws {
        let tree = Parser.parse(source: "struct A: App { var body: some Scene { WindowGroup { } } }")
        // `#require` rather than `try?` + `guard`: an empty result here means the
        // helper stopped finding nodes, and that must fail the test rather than
        // pass it vacuously.
        let node = try #require(Self.descendants(of: StructDeclSyntax.self, in: tree).first)

        #expect(isSwiftUIView(node))
        #expect(isSwiftUIViewOnly(node) == false)
    }

    /// **Totality** for the `ForEach` predicates, over every call expression the
    /// parser yields — including the malformed sources.
    @Test
    func forEachPredicatesAreTotalOverEveryParsedCall() async {
        await propertyCheck(input: Self.sourceGen) { source in
            let tree = Parser.parse(source: source)
            for node in Self.descendants(of: FunctionCallExprSyntax.self, in: tree) {
                _ = isForEachCollectionSafeForSelfID(node)
                _ = inferForEachElementType(node)
            }
        }
    }

    /// Determinism over the syntax surface: parsing the same source twice yields
    /// the same verdicts.
    ///
    /// Cheap, and it guards the thing a syntax predicate is most likely to get
    /// wrong once someone adds a cache — a per-node memo keyed on something that
    /// is not stable across parses.
    @Test
    func predicatesAreDeterministicAcrossReparses() async {
        await propertyCheck(input: Self.sourceGen) { source in
            let first = Self.descendants(of: StructDeclSyntax.self, in: Parser.parse(source: source))
                .map { [isSwiftUIView($0), isSwiftUIViewOnly($0)] }
            let second = Self.descendants(of: StructDeclSyntax.self, in: Parser.parse(source: source))
                .map { [isSwiftUIView($0), isSwiftUIViewOnly($0)] }
            #expect(first == second)
        }
    }
}

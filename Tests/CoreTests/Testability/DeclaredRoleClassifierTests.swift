@testable import Core
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Reading a role off a *declaration's* signature.
///
/// The closure rule has it easy: a closure passed to `sorted` is a comparator because the call site
/// says so. A declaration has no call site, so this reads the signature — and a role travels to
/// another tool as a claim, where three of them mean "a correct implementation cannot fail this
/// law". Getting one wrong proposes a red test against correct code.
///
/// So the silences below carry the weight. Every case is either entailed by the shape or `nil`.
@Suite("Role read off a declared signature")
struct DeclaredRoleClassifierTests {

    private func role(_ source: String, isPartial: Bool = false) -> PBTSeedRole? {
        let syntax = Parser.parse(source: source)
        guard let decl = syntax.statements.compactMap({
            $0.item.as(FunctionDeclSyntax.self)
        }).first else {
            Issue.record("fixture did not parse as a function declaration")
            return nil
        }
        return DeclaredRoleClassifier.role(of: decl, isPartial: isPartial)
    }

    // MARK: - Entailed

    @Test("a Bool-returning function of its inputs is a predicate")
    func boolIsPredicate() {
        #expect(role("func isValid(_ name: String) -> Bool { true }") == .predicate)
        #expect(role("func matches(path: String, pattern: String) -> Bool { true }") == .predicate)
    }

    @Test("two same-typed arguments plus an ordering name is a comparator")
    func orderingNameIsComparator() {
        #expect(role("func compare(_ lhs: Rule, _ rhs: Rule) -> Bool { true }") == .comparator)
        #expect(role("func precedes(_ lhs: Int, _ rhs: Int) -> Bool { true }") == .comparator)
    }

    // MARK: - The ambiguity the name resolves

    @Test("two same-typed arguments WITHOUT an ordering name stays a predicate")
    func relationIsNotAComparator() {
        // `(T, T) -> Bool` is genuinely ambiguous. `isEqual` and `matches` have exactly a
        // comparator's shape and owe no ordering whatsoever; claiming one would assert a strict
        // weak ordering that correct code fails. Predicate is the weaker, true claim.
        #expect(role("func isEqual(_ lhs: Rule, _ rhs: Rule) -> Bool { true }") == .predicate)
        #expect(role("func sharesPrefix(_ lhs: String, _ rhs: String) -> Bool { true }") == .predicate)
    }

    @Test("an ordering name on mismatched types is not a comparator")
    func orderingNeedsMatchingTypes() {
        #expect(role("func compare(_ lhs: Rule, _ rhs: Int) -> Bool { true }") == .predicate)
    }

    @Test("an ordering word inside a longer name does not count")
    func orderingNameIsWholeNameOnly() {
        // Matched against the whole name: in `compareCount` the head noun has moved, and the
        // function returns a comparison *result* rather than being the ordering.
        #expect(role("func compareCount(_ lhs: Rule, _ rhs: Rule) -> Bool { true }") == .predicate)
    }

    // MARK: - Conjectured

    @Test("a same-type endomorphism is a normalizer, not an entailed role")
    func endomorphismIsNormalizer() {
        let normalizer = role("func normalize(_ path: String) -> String { path }")
        #expect(normalizer == .normalizer)
        // Round-trip and idempotence are conjectures for this shape, and the manifest must say so.
        #expect(normalizer?.impliesEntailedLaw == false)
    }

    // MARK: - Silence

    @Test("a throwing Bool function claims nothing")
    func partialIsNotAPredicate() {
        // The predicate law is TOTALITY. A function that throws is by definition not total over
        // its domain, so claiming the role would hand the reader a law its own subject is
        // documented to fail.
        #expect(role("func isValid(_ name: String) throws -> Bool { true }", isPartial: true) == nil)
    }

    @Test("a plain transform claims nothing")
    func transformIsUnclassified() {
        // `(A) -> B` owes nothing the shape can name. Silence beats a guess.
        #expect(role("func count(of text: String) -> Int { 0 }") == nil)
    }

    @Test("a zero-argument function claims nothing")
    func nullaryIsUnclassified() {
        #expect(role("func makeDefault() -> Config { Config() }") == nil)
    }

    @Test("a Void function claims nothing")
    func voidIsUnclassified() {
        #expect(role("func apply(_ rule: Rule) { }") == nil)
        #expect(role("func apply(_ rule: Rule) -> Void { }") == nil)
    }

    // MARK: - Every claimed role agrees with its own entailment flag

    @Test("nothing conjectured is ever claimed as entailed")
    func entailmentClaimsAreConsistent() {
        // The classifier is the producer of a claim `SeedRoleContractTests` checks from the other
        // repository. Only comparator, predicate and partition may report `impliesEntailedLaw`.
        let claimed: [PBTSeedRole?] = [
            role("func isValid(_ name: String) -> Bool { true }"),
            role("func compare(_ lhs: Rule, _ rhs: Rule) -> Bool { true }"),
            role("func normalize(_ path: String) -> String { path }")
        ]
        for case let entailed? in claimed where entailed.impliesEntailedLaw {
            #expect([.comparator, .predicate, .partition].contains(entailed))
        }
    }
}

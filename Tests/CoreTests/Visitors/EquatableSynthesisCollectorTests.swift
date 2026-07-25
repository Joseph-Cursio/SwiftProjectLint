import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// `EquatableConformanceCollector` must record types the **compiler** makes
/// `Equatable`, not only those that say so in source.
///
/// ## Why this matters more than it looks
///
/// The set gates seeding. `PropertyTestCandidacy.returnIsAssertable` refuses a
/// candidate whose return type is not known-`Equatable`, on the sound reasoning
/// that a test must be able to assert on the result. So a type missing from this
/// index does not produce a worse suggestion — it produces **no suggestion**, and
/// the function disappears from the seed manifest without a word.
///
/// Measured on this codebase: that alone kept `LintConfiguration.resolveRules`
/// out of the manifest. Its purity verdict was `.pure` the whole time; the only
/// thing standing between it and a seed was that `RuleIdentifier` — an enum
/// `Equatable` by language guarantee — was not in the set.
///
/// ## The rule, and why it is sound
///
/// An enum with **no associated values** is `Equatable` and `Hashable` whether or
/// not it declares them; the compiler synthesises both. A raw-value enum cannot
/// carry associated values, so `enum R: String` and bare `enum C { case a, b }`
/// are the same case. An enum *with* associated values is `Equatable` only when
/// declared, so it stays gated on the declaration.
///
/// That is a language guarantee rather than a heuristic, which is what makes
/// widening the index here safe: it cannot admit a type that is not really
/// `Equatable`.
@Suite
struct EquatableSynthesisCollectorTests {

    private func collected(_ source: String) -> Set<String> {
        let collector = EquatableConformanceCollector()
        collector.walk(Parser.parse(source: source))
        return collector.collectedTypes
    }

    // MARK: - Synthesised

    /// The case that motivated this: a raw-value enum declaring `CaseIterable`
    /// and `Codable` but never `Equatable`.
    @Test
    func rawValueEnumIsEquatableWithoutSayingSo() {
        let types = collected("enum RuleIdentifier: String, CaseIterable, Codable { case forceTry = \"Force Try\" }")
        #expect(types.contains("RuleIdentifier"))
    }

    /// No raw value either — payload-free is enough on its own.
    @Test
    func payloadFreeEnumIsEquatable() {
        #expect(collected("enum PatternCategory { case codeQuality, performance }").contains("PatternCategory"))
    }

    @Test
    func multiCaseAndSingleCaseEnumsBothQualify() {
        #expect(collected("enum Solo { case only }").contains("Solo"))
        #expect(collected("enum Trio: Int { case a = 1, b = 2, c = 3 }").contains("Trio"))
    }

    /// An empty enum — a namespace — is vacuously payload-free. Recording it is
    /// harmless: nothing returns a value of an uninhabited type.
    @Test
    func namespaceEnumIsRecorded() {
        #expect(collected("enum Namespace {}").contains("Namespace"))
    }

    // MARK: - Not synthesised

    /// The boundary that keeps the widening sound. An enum with a payload is
    /// `Equatable` only if it declares it — the compiler will not synthesise
    /// conformance the author did not ask for.
    @Test
    func enumWithAssociatedValuesIsNotAssumedEquatable() {
        #expect(collected("enum Outcome { case ok, failed(Error) }").contains("Outcome") == false)
    }

    /// …and declaring it is still honoured, so the payload case is not simply
    /// excluded.
    @Test
    func enumWithAssociatedValuesThatDeclaresEquatableIsRecorded() {
        #expect(collected("enum Outcome: Equatable { case ok, failed(String) }").contains("Outcome"))
    }

    /// One payload-carrying case is enough to disqualify the whole enum, even
    /// alongside payload-free ones.
    @Test
    func oneAssociatedValueDisqualifiesTheEnum() {
        #expect(collected("enum Mixed { case none, some(Int), other }").contains("Mixed") == false)
    }

    /// Structs are never automatically `Equatable`, however simple. The synthesis
    /// rule is enum-only and must not leak.
    @Test
    func structsAreStillGatedOnDeclaration() {
        #expect(collected("struct Point { var x = 0; var y = 0 }").contains("Point") == false)
        #expect(collected("struct Point: Equatable { var x = 0 }").contains("Point"))
    }

    /// Classes are never automatically `Equatable` either.
    @Test
    func classesAreStillGatedOnDeclaration() {
        #expect(collected("class Node { var value = 0 }").contains("Node") == false)
    }

    // MARK: - Existing behaviour preserved

    @Test(
        "declared conformances still qualify a type",
        arguments: ["Equatable", "Hashable", "Comparable"]
    )
    func declaredConformancesStillQualify(conformance: String) {
        #expect(collected("struct Value: \(conformance) { var x = 0 }").contains("Value"))
    }

    @Test
    func conformanceViaExtensionStillQualifies() {
        let types = collected("struct Value { var x = 0 }\nextension Value: Hashable {}")
        #expect(types.contains("Value"))
    }

    /// A payload-carrying enum made `Equatable` in a separate extension — the
    /// cross-file path the collector exists for — still resolves.
    @Test
    func payloadEnumMadeEquatableInAnExtensionQualifies() {
        let types = collected("enum Outcome { case failed(String) }\nextension Outcome: Equatable {}")
        #expect(types.contains("Outcome"))
    }
}

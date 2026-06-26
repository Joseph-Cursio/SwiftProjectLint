import PropertyBased
import enum SwiftEffectInference.Effect
import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Property-based laws for `EffectSymbolTable` — the cross-file accumulation
/// and multi-hop inference engine the idempotency rules sit on top of. These
/// exercise behaviours the per-fixture example tests can't span:
///
/// 1. **Cross-file merge is order-independent (confluent).** Merging the same
///    set of annotated files in any order yields identical entries. The
///    collision policy withdraws a signature whenever two annotations for it
///    disagree, so the surviving set is a function of the *multiset* of
///    annotations, never the file ordering — but only if withdrawal is
///    permanent and order-blind. A regression that made withdrawal depend on
///    arrival order (e.g. "last writer wins") passes fixed-order fixtures and
///    dies here.
/// 2. **Multi-hop inference is idempotent at its fixed point.** Once the
///    iteration converges, applying it again changes nothing. This guards the
///    convergence check itself: a loop that stops one pass early, or that
///    fails to merge monotonically, would keep moving on re-application.
@Suite
struct EffectSymbolTableLawsTests {

    // MARK: - Cross-file merge order-independence

    /// One annotated single-function file: a function name (drawn from a small
    /// pool to force collisions) and a declared effect token.
    private struct AnnotatedFile: Sendable, Equatable {
        let name: String
        let token: String
    }

    private static func file(_ spec: AnnotatedFile) -> SourceFileSyntax {
        Parser.parse(source: """
        /// @lint.effect \(spec.token)
        func \(spec.name)() {}
        """)
    }

    private static func mergedEntries(
        _ specs: [AnnotatedFile]
    ) -> [FunctionSignature: EffectSymbolTable.Entry] {
        var table = EffectSymbolTable()
        for spec in specs {
            table.merge(source: file(spec))
        }
        return table.entriesBySignature
    }

    /// 3 names × 4 effect tokens. Few names ⇒ frequent same-signature
    /// collisions, which is exactly the path order-independence must survive.
    private static let fileGen = Gen<AnnotatedFile>.oneOf(
        Gen.always(AnnotatedFile(name: "save", token: "idempotent")),
        Gen.always(AnnotatedFile(name: "save", token: "observational")),
        Gen.always(AnnotatedFile(name: "save", token: "externally_idempotent")),
        Gen.always(AnnotatedFile(name: "save", token: "non_idempotent")),
        Gen.always(AnnotatedFile(name: "send", token: "idempotent")),
        Gen.always(AnnotatedFile(name: "send", token: "observational")),
        Gen.always(AnnotatedFile(name: "send", token: "externally_idempotent")),
        Gen.always(AnnotatedFile(name: "send", token: "non_idempotent")),
        Gen.always(AnnotatedFile(name: "fetch", token: "idempotent")),
        Gen.always(AnnotatedFile(name: "fetch", token: "observational")),
        Gen.always(AnnotatedFile(name: "fetch", token: "externally_idempotent")),
        Gen.always(AnnotatedFile(name: "fetch", token: "non_idempotent"))
    )

    private static let corpusGen = fileGen.array(of: 1...6)

    @Test
    func crossFileMerge_isOrderIndependent() async {
        await propertyCheck(input: Self.corpusGen) { specs in
            let forward = Self.mergedEntries(specs)
            let reversed = Self.mergedEntries(specs.reversed())
            let sorted = Self.mergedEntries(
                specs.sorted { ($0.name, $0.token) < ($1.name, $1.token) }
            )
            // Two distinct permutations (reverse and a canonical sort) must
            // both reproduce the forward-order result.
            #expect(forward == reversed)
            #expect(forward == sorted)
        }
    }

    // MARK: - Multi-hop inference fixpoint idempotence

    /// Chain length is capped below `maxHops` (default 5) so the first
    /// application is guaranteed to converge — otherwise a re-application would
    /// legitimately keep inferring and idempotence would not (and should not)
    /// hold.
    private static let chainLengthGen = Gen<Int>.oneOf(
        Gen.always(1),
        Gen.always(2),
        Gen.always(3),
        Gen.always(4)
    )

    private static let anchorTokenGen = Gen<String>.oneOf(
        Gen.always("idempotent"),
        Gen.always("observational"),
        Gen.always("externally_idempotent"),
        Gen.always("non_idempotent")
    )

    /// A declared `anchor` followed by `length` un-annotated helpers, each
    /// calling the previous one — a chain that only multi-hop inference can
    /// resolve end to end.
    private static func chainSource(length: Int, anchorToken: String) -> SourceFileSyntax {
        var lines = [
            "/// @lint.effect \(anchorToken)",
            "func anchor() {}"
        ]
        var previous = "anchor"
        for index in 1...length {
            let name = "helper\(index)"
            lines.append("func \(name)() { \(previous)() }")
            previous = name
        }
        return Parser.parse(source: lines.joined(separator: "\n"))
    }

    @Test
    func multiHopInference_isIdempotentAtFixpoint() async {
        await propertyCheck(input: Self.chainLengthGen, Self.anchorTokenGen) { length, anchorToken in
            let source = Self.chainSource(length: length, anchorToken: anchorToken)
            let helpers = (1...length).map {
                FunctionSignature(name: "helper\($0)", argumentLabels: [])
            }

            var table = EffectSymbolTable()
            table.merge(source: source)

            // Resolver returns nil throughout: the chain is anchored solely by
            // the declared `anchor`, so every inferred helper effect traces
            // back to it through the upward chain.
            table.applyUpwardInference(to: [source], multiHop: true) { _ in nil }
            let afterFirst = helpers.map { table.upwardInference(for: $0)?.effect }

            // Non-vacuity: every helper in the chain is actually inferred, so
            // the idempotence check below has real content to compare.
            #expect(afterFirst.allSatisfy { $0 != nil })

            table.applyUpwardInference(to: [source], multiHop: true) { _ in nil }
            let afterSecond = helpers.map { table.upwardInference(for: $0)?.effect }

            #expect(afterFirst == afterSecond)
        }
    }
}

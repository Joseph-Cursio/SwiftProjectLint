import Testing
import PropertyBased
@testable import SwiftProjectLintVisitors

/// Property-based validation of `Effect.lub`.
///
/// The lattice ordering (strictest first):
///
///     observational < idempotent < externallyIdempotent < nonIdempotent
///
/// Two design notes for these tests:
///
/// 1. `externallyIdempotent` is generated only with `keyParameter: nil`. The
///    associated-value variants share a rank; when two same-rank effects
///    appear in a single lub call, the implementation returns the first one
///    encountered (strict `>` comparison in `leastUpperBound`). That tie-break
///    is rank-correct but breaks naive equality assertions, so the canonical
///    form keeps Equatable-based laws clean.
/// 2. `rank` is `private` in `BodyEffectInferrer`, so the test mirrors the
///    expected ordering as `expectedRank` below. If the implementation's
///    lattice positions ever change, the test oracle disagrees with lub's
///    output and the laws fail loudly — surfacing the change explicitly.
@Suite
struct LatticeLawsTests {

    private static let effectGen = Gen<Effect>.oneOf(
        Gen.always(.observational),
        Gen.always(.idempotent),
        Gen.always(.externallyIdempotent(keyParameter: nil)),
        Gen.always(.nonIdempotent)
    )

    private static func expectedRank(_ effect: Effect) -> Int {
        switch effect {
        case .observational: 0
        case .idempotent: 1
        case .externallyIdempotent: 2
        case .nonIdempotent: 3
        }
    }

    // MARK: - Single-element identity

    @Test
    func lubOfSingleton_isThatElement() async {
        await propertyCheck(input: Self.effectGen) { effect in
            #expect(Effect.lub(of: [effect]) == effect)
        }
    }

    // MARK: - Duplication idempotence

    @Test
    func lubOfDuplicates_isThatElement() async {
        await propertyCheck(input: Self.effectGen) { effect in
            #expect(Effect.lub(of: [effect, effect]) == effect)
        }
    }

    // MARK: - Commutativity (rank-level — see file header for tie-break note)

    @Test
    func lubCommutes_onRank() async {
        await propertyCheck(input: Self.effectGen, Self.effectGen) { lhs, rhs in
            let lubLR = try #require(Effect.lub(of: [lhs, rhs]))
            let lubRL = try #require(Effect.lub(of: [rhs, lhs]))
            #expect(Self.expectedRank(lubLR) == Self.expectedRank(lubRL))
        }
    }

    // MARK: - Associativity (rank-level)

    @Test
    func lubAssociates_onRank() async {
        await propertyCheck(
            input: Self.effectGen,
            Self.effectGen,
            Self.effectGen
        ) { lhs, mid, rhs in
            let midRhs = try #require(Effect.lub(of: [mid, rhs]))
            let leftFolded = try #require(Effect.lub(of: [lhs, midRhs]))

            let lhsMid = try #require(Effect.lub(of: [lhs, mid]))
            let rightFolded = try #require(Effect.lub(of: [lhsMid, rhs]))

            #expect(Self.expectedRank(leftFolded) == Self.expectedRank(rightFolded))
        }
    }

    // MARK: - Upper bound: lub dominates each input

    @Test
    func lubDominates_eachInput() async {
        await propertyCheck(input: Self.effectGen, Self.effectGen) { lhs, rhs in
            let bound = try #require(Effect.lub(of: [lhs, rhs]))
            #expect(Self.expectedRank(bound) >= Self.expectedRank(lhs))
            #expect(Self.expectedRank(bound) >= Self.expectedRank(rhs))
        }
    }

    // MARK: - Membership: lub of a finite set is one of its elements (by rank)

    @Test
    func lubMembership_byRank() async {
        await propertyCheck(input: Self.effectGen, Self.effectGen) { lhs, rhs in
            let bound = try #require(Effect.lub(of: [lhs, rhs]))
            let boundRank = Self.expectedRank(bound)
            #expect(boundRank == Self.expectedRank(lhs) || boundRank == Self.expectedRank(rhs))
        }
    }

    // MARK: - Empty input edge case

    @Test
    func lubOfEmpty_isNil() {
        #expect(Effect.lub(of: []) == nil)
    }
}

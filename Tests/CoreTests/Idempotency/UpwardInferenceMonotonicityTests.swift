import PropertyBased
import enum SwiftEffectInference.Effect
import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Property-based validation that `UpwardEffectInferrer.inferEffects` is
/// **monotone in its resolver**: strengthening any callee's effect — raising it
/// in the chain `observational < idempotent < externallyIdempotent <
/// nonIdempotent` — can only raise, never lower, each caller's inferred effect.
///
/// This is the load-bearing correctness contract of body inference that the
/// `LatticeLawsTests` algebra cannot see. `inferEffects` assigns each function
/// the lub of its callees' effects, and lub is monotone, so the whole inference
/// must be too. A regression that drops or mis-filters a high-rank callee — say
/// an escaping-closure gate that over-triggers, or a `filter` that discards the
/// rank-determining call — would pass every fixed-input example test yet violate
/// this law on the first generated counterexample.
@Suite
struct UpwardInferenceMonotonicityTests {

    /// One unannotated caller invoking three named callees. The resolver
    /// supplies each callee's effect; the caller's inferred effect is their lub.
    private static let source = Parser.parse(source: """
    func caller() {
        alpha()
        beta()
        gamma()
    }
    """)

    private static let calleeNames = ["alpha", "beta", "gamma"]

    private static let effectGen = Gen<Effect>.oneOf(
        Gen.always(.observational),
        Gen.always(.idempotent),
        Gen.always(.externallyIdempotent(keyParameter: nil)),
        Gen.always(.nonIdempotent)
    )

    /// One effect per callee.
    private static let tripleGen = effectGen.array(of: 3)

    private static let callerSignature = FunctionSignature(name: "caller", argumentLabels: [])

    /// Builds a resolver mapping each named call to its assigned effect at
    /// depth 0 (an anchor, matching how declared / heuristic effects enter the
    /// inference). Unknown calls resolve to `nil` and contribute nothing.
    private static func resolver(
        _ assignment: [String: Effect]
    ) -> (FunctionCallExprSyntax) -> UpwardInference? {
        { call in
            guard let signature = FunctionSignature.from(call: call),
                  let effect = assignment[signature.name] else { return nil }
            return UpwardInference(effect: effect, depth: 0)
        }
    }

    @Test
    func raisingAnyCalleeEffect_neverLowersInferredEffect() async {
        await propertyCheck(input: Self.tripleGen, Self.tripleGen) { lhs, rhs in
            // Per callee, the lower-rank effect is the baseline and the
            // higher-rank one is the strengthened variant. This makes `raised`
            // dominate `base` pointwise by construction, over the *same* set of
            // contributing callees — isolating the effect of strengthening from
            // the effect of adding or removing callees.
            var base: [String: Effect] = [:]
            var raised: [String: Effect] = [:]
            for (index, name) in Self.calleeNames.enumerated() {
                let first = lhs[index]
                let second = rhs[index]
                let lower = first.rank <= second.rank ? first : second
                let higher = first.rank <= second.rank ? second : first
                base[name] = lower
                raised[name] = higher
            }

            let baseResult = UpwardEffectInferrer.inferEffects(
                in: Self.source,
                resolveCalleeEffect: Self.resolver(base)
            )
            let raisedResult = UpwardEffectInferrer.inferEffects(
                in: Self.source,
                resolveCalleeEffect: Self.resolver(raised)
            )

            // All three callees resolve to an effect, so the caller is inferred
            // under both assignments.
            let baseEffect = try #require(baseResult[Self.callerSignature]).effect
            let raisedEffect = try #require(raisedResult[Self.callerSignature]).effect

            #expect(raisedEffect.rank >= baseEffect.rank)
        }
    }

    /// A concrete anchor for the property above: when even one callee is raised
    /// to `nonIdempotent`, the caller is forced to `nonIdempotent` regardless of
    /// the other callees — the top of the chain dominates.
    @Test
    func raisingOneCalleeToNonIdempotent_forcesNonIdempotentCaller() {
        let assignment: [String: Effect] = [
            "alpha": .observational,
            "beta": .nonIdempotent,
            "gamma": .idempotent
        ]
        let result = UpwardEffectInferrer.inferEffects(
            in: Self.source,
            resolveCalleeEffect: Self.resolver(assignment)
        )
        #expect(result[Self.callerSignature]?.effect == .nonIdempotent)
    }
}

import SwiftEffectInference
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Phase-2.3 upward inference fixtures. Body analysis computes an inferred
/// effect for an un-annotated function from the lattice lub of its direct
/// callees' effects. Declared effects always win; upward inference fills
/// the gap between "declared" and "heuristic-downward" in the rule lookup
/// cascade.
@Suite
struct UpwardInferenceTests {

    // MARK: - Lattice lub

    @Test
    func lub_empty_isNil() {
        #expect(Effect.lub(of: []) == nil)
    }

    @Test
    func lub_onlyObservational_isObservational() {
        #expect(
            Effect.lub(of: [.observational, .observational])
                == .observational
        )
    }

    @Test
    func lub_observationalAndIdempotent_isIdempotent() {
        #expect(
            Effect.lub(of: [.observational, .idempotent])
                == .idempotent
        )
    }

    @Test
    func lub_idempotentAndExternallyIdempotent_isExternallyIdempotent() {
        #expect(
            Effect.lub(
                of: [.idempotent, .externallyIdempotent(keyParameter: "k")]
            ) == .externallyIdempotent(keyParameter: "k")
        )
    }

    @Test
    func lub_nonIdempotentDominates() {
        #expect(
            Effect.lub(
                of: [.observational, .idempotent, .externallyIdempotent(keyParameter: nil), .nonIdempotent]
            ) == .nonIdempotent
        )
    }

    // MARK: - Body walk semantics

    /// Helper that wraps the bare-effect resolver into the
    /// `BodyInference?` shape the inferrer now requires. All single-pass
    /// fixtures here treat resolver-supplied effects as anchors (depth 0),
    /// matching the symbol-table's behaviour for declared / heuristic
    /// effects.
    private func infer(
        _ source: String,
        resolve: @escaping (FunctionCallExprSyntax) -> DeclaredEffect?
    ) -> [FunctionSignature: BodyInference] {
        BodyEffectInferrer.inferEffects(in: Parser.parse(source: source)) { call in
            guard let effect = resolve(call) else { return nil }
            return BodyInference(effect: effect, depth: 0)
        }
    }

    @Test
    func unannotatedCallerWithNonIdempotentCallee_infersNonIdempotent() {
        let source = """
        func caller() {
            callee()
        }
        """
        let result = infer(source) { _ in .nonIdempotent }
        let sig = FunctionSignature(name: "caller", argumentLabels: [])
        #expect(result[sig]?.effect == .nonIdempotent)
        #expect(result[sig]?.depth == 1)
    }

    @Test
    func annotatedCaller_notInferred() {
        // The inferrer skips any declaration carrying `@lint.effect`. The
        // user's annotation is authoritative and must not be second-guessed.
        let source = """
        /// @lint.effect idempotent
        func caller() {
            callee()
        }
        """
        let result = infer(source) { _ in .nonIdempotent }
        let sig = FunctionSignature(name: "caller", argumentLabels: [])
        #expect(result[sig] == nil)
    }

    @Test
    func escapingClosureBoundary_notTraversed() {
        // Calls inside `Task { }` / `withTaskGroup` / `.task` are in a
        // different retry context. Upward inference stops at those
        // boundaries, same as the rule visitors.
        //
        // Resolver returns effects only for the NAMED callees we care about
        // (`callee`), not for the escape-introducing wrappers (`Task`).
        // Realistic resolvers behave the same way — `Task()` itself is
        // neither annotated nor heuristically inferable, so lookup returns
        // nil and it contributes nothing. This fixture verifies the body
        // walk skips the closure body even when the closure would otherwise
        // contain recognised effects.
        let source = """
        func caller() {
            Task {
                callee()
            }
        }
        """
        let result = infer(source) { call in
            guard let sig = FunctionSignature.from(call: call),
                  sig.name == "callee" else { return nil }
            return .nonIdempotent
        }
        let sig = FunctionSignature(name: "caller", argumentLabels: [])
        // `callee()` sits inside an escaping closure boundary and does not
        // contribute. `Task(...)` itself has no effect in the resolver.
        // Net result: no effects collected, no inference.
        #expect(result[sig] == nil)
    }

    @Test
    func nestedFunctionNotTreatedAsInnerBody() {
        // A nested function is its own inference site. The outer function's
        // body walk must stop at the inner function's boundary — otherwise
        // the inner's callees would leak into the outer's inferred effect.
        let source = """
        func outer() {
            func inner() {
                callee()
            }
            otherCall()
        }
        """
        let result = infer(source) { call in
            let sig = FunctionSignature.from(call: call)
            return sig?.name == "callee" ? .nonIdempotent : nil
        }
        let outerSig = FunctionSignature(name: "outer", argumentLabels: [])
        let innerSig = FunctionSignature(name: "inner", argumentLabels: [])
        // outer should NOT inherit from inner's body (no evidence from
        // otherCall resolver); inner should infer non_idempotent.
        #expect(result[outerSig] == nil)
        #expect(result[innerSig]?.effect == .nonIdempotent)
    }

    @Test
    func bodyWithNoRecognisedCalls_producesNoInference() {
        let source = """
        func pureLooking() {
            let x = 1 + 2
            _ = x
        }
        """
        let result = infer(source) { _ in nil }
        #expect(result.isEmpty)
    }

    // MARK: - Rank ordering matches the proposal's lattice

    @Test
    func rankOrdering_observationalBelowIdempotent() {
        #expect(
            Effect.lub(of: [.idempotent, .observational])
                == .idempotent
        )
    }

    @Test
    func rankOrdering_externallyIdempotentAboveIdempotent() {
        #expect(
            Effect.lub(
                of: [.idempotent, .externallyIdempotent(keyParameter: nil)]
            ) == .externallyIdempotent(keyParameter: nil)
        )
    }
}

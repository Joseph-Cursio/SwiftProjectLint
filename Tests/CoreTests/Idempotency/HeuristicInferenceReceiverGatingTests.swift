import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Receiver-type gating fixtures for the heuristic inferrer: stdlib
/// collection exclusions and user-defined receiver anchors.
@Suite
struct HeuristicInferenceReceiverGatingTests {

    // MARK: - Receiver-type gating (Phase 2 second slice)

    @Test
    func arrayLiteralAppend_isExcluded() throws {
        // `[1, 2].append(3)` — bare-name `append` is whitelisted but the
        // receiver resolves to an Array literal. Stdlib exclusion fires.
        let call = try firstCall(in: "func f() { [1, 2].append(3) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func localArrayAppend_isExcluded() throws {
        // Regression fixture for the R5 Run D noise diagnostic: untyped
        // local binding initialised from an array literal, then mutated
        // via `append`.
        let source = """
        func f(owner: User) {
            var users = [owner]
            users.append(other)
        }
        """
        let call = try memberCall(method: "append", in: source)
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func typedArrayParameterAppend_isExcluded() throws {
        let call = try memberCall(
            method: "append",
            in: "func f(xs: [Int]) { xs.append(1) }"
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func userDefinedQueueAppend_stillFires() throws {
        // User-defined receiver type: bare-name heuristic proceeds
        // unchanged. This is the anchor test ensuring the gate doesn't
        // over-reach and silence legitimate catches on non-stdlib types.
        let call = try memberCall(
            method: "append",
            in: #"func f(q: UserQueue) { q.append("a") }"#
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func setInsert_isExcluded() throws {
        // Set.insert is idempotent by set semantics. Previously the
        // bare-name `insert` heuristic flagged it as non_idempotent.
        let call = try memberCall(
            method: "insert",
            in: "func f(s: Set<Int>) { s.insert(1) }"
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func userDefinedSetInsert_stillFires() throws {
        // User-defined `UserSet` — not stdlib Set. The gate must not
        // apply; `insert` still fires as non_idempotent.
        let call = try memberCall(
            method: "insert",
            in: "func f(s: UserSet) { s.insert(1) }"
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func excludedPair_producesNoReason() throws {
        // Mirrors the `infer(call:)` suppression — `inferenceReason`
        // must return nil on excluded pairs so visitors don't emit stray
        // provenance prose when the effect itself was suppressed.
        let call = try memberCall(method: "append", in: "func f() { [1, 2].append(3) }")
        #expect(HeuristicEffectInferrer.inferenceReason(for: call) == nil)
    }
}

import enum SwiftEffectInference.Effect
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

extension HeuristicInferenceTests {
    // MARK: - Observational requires BOTH receiver shape AND level method

    @Test
    func loggerInfo_infersObservational() throws {
        let call = try firstCall(in: "func f() { logger.info(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func uppercaseLoggerDebug_infersObservational() throws {
        let call = try firstCall(in: "func f() { Logger.debug(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func requestLoggerWarning_infersObservational() throws {
        // Suffixed-logger receivers like `requestLogger` pattern-match the
        // "contains 'log'" check and produce observational.
        let call = try firstCall(in: "func f() { requestLogger.warning(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func bareInfoWithoutReceiver_doesNotInferObservational() throws {
        // `info()` called on its own could be anything — an observable or a
        // domain method. Observational inference requires the logger-receiver
        // signal; without it, the inferrer stays silent.
        let call = try firstCall(in: "func f() { info(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func nonLoggerReceiverDebug_doesNotInferObservational() throws {
        // `view.debug()` has a debug-level method name but the receiver
        // doesn't look like a logger. Stay silent.
        let call = try firstCall(in: "func f() { view.debug() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Chained receiver (context.logger.method — round-9 follow-on)
    //
    // Round-9 validation on swift-aws-lambda-runtime surfaced a gap:
    // `context.logger.info(...)` didn't match the observational heuristic
    // because `callParts` only extracted the immediate base identifier
    // (`context`), which isn't logger-shaped. The fix walks one level
    // deeper on chained member access and tests the segment immediately
    // before the callee — the segment that actually exposes the method.

    @Test
    func contextLoggerInfo_infersObservational_chainedReceiver() throws {
        let call = try firstCall(in: "func f() { context.logger.info(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func contextLoggerError_infersObservational_chainedReceiver() throws {
        let call = try firstCall(in: "func f() { context.logger.error(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func selfLoggerDebug_infersObservational_chainedReceiver() throws {
        // Mirrors the same pattern but with `self` — a common shape for
        // instance methods that carry their own logger.
        let call = try firstCall(in: "func f() { self.logger.debug(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func requestLoggerFromContext_infersObservational_chainedReceiver() throws {
        // `context.requestLogger.warning(...)` — immediate-parent segment
        // is `requestLogger`, which pattern-matches the suffixed-logger rule.
        let call = try firstCall(in: "func f() { context.requestLogger.warning(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func deeplyChainedLogger_infersObservational() throws {
        // Three-level chain: `app.context.logger.info(...)` — still finds
        // the logger-shaped segment as the immediate parent of `info`.
        let call = try firstCall(in: "func f() { app.context.logger.info(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .observational)
    }

    @Test
    func chainedNonLoggerReceiver_doesNotInferObservational() throws {
        // Chained call where no segment looks like a logger. Stay silent.
        // `view.debug()` already tests single-level; this covers the
        // two-level variant to confirm the extension doesn't go too loose.
        let call = try firstCall(in: "func f() { app.view.debug() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func chainedLoggerNonLevelMethod_doesNotInferObservational() throws {
        // `context.logger.flush()` — logger-shaped receiver but a non-level
        // method. Observational heuristic still requires both signals.
        let call = try firstCall(in: "func f() { context.logger.flush() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Names deliberately left out of the allowlist

    @Test
    func save_isNotInferred() throws {
        // `save` has too many idempotent interpretations (set-current-value,
        // upsert-like semantics) to classify as non_idempotent by name alone.
        let call = try firstCall(in: "func f() { save(row) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func put_isNotInferred() throws {
        // REST PUT is idempotent; dictionary `put` is often idempotent;
        // arbitrary `put` is ambiguous. Keep out of the allowlist.
        let call = try firstCall(in: "func f() { store.put(k, v) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func update_bareName_firesOnNonStdlibReceivers() throws {
        // `update` is in the bare non-idempotent list. Catches
        // non-Fluent DB surfaces where an adopter has an
        // `@Dependency(\.database)`-style accessor with `updateX`
        // naming — the pointfreeco-shape case. Fires on any
        // non-stdlib receiver; the stdlib-collection exclusions
        // (Set.update, Dictionary.updateValue) are handled via
        // `StdlibExclusions`.
        let call = try firstCall(in: "func f() { database.update(row) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func setUpdateWith_isExcluded() throws {
        // `Set.update(with:)` leaves the set in the same final state
        // on repeat invocation (set-idempotent semantics). Stdlib
        // exclusion must suppress the bare-name `update` match.
        let call = try memberCall(
            method: "update",
            in: "func f(s: Set<Int>) { s.update(with: 1) }"
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func prefixUpdateGiftStatus_firesOnUnresolvedReceiver() throws {
        // Regression fixture for the pointfreeco adopter case:
        // `database.updateGiftStatus(...)` via a swift-dependencies
        // property. Receiver `database` resolves to `.unresolved`
        // (not stdlib), so the prefix-match path fires.
        let call = try memberCall(
            method: "updateGiftStatus",
            in: "func f() { database.updateGiftStatus(id, status, deliverNow) }"
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func write_isNotInferred() throws {
        // `file.write` is often atomic and retry-safe; no blanket
        // non-idempotent classification.
        let call = try firstCall(in: "func f() { file.write(data) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func unrecognisedName_returnsNil() throws {
        let call = try firstCall(in: "func f() { doThing(x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Reason strings

    @Test
    func inferenceReason_bareName() throws {
        let call = try firstCall(in: "func f() { insert(x) }")
        let reason = try #require(HeuristicEffectInferrer.inferenceReason(for: call))
        #expect(reason.contains("insert"))
        #expect(reason.contains("callee name"))
    }

    @Test
    func inferenceReason_loggerReceiver() throws {
        let call = try firstCall(in: "func f() { logger.info(\"x\") }")
        let reason = try #require(HeuristicEffectInferrer.inferenceReason(for: call))
        #expect(reason.contains("logger"))
        #expect(reason.contains("info"))
        #expect(reason.contains("logger-shaped"))
    }
}

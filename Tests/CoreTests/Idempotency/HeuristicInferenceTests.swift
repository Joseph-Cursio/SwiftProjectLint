import enum SwiftEffectInference.Effect
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Phase-2 heuristic inference fixtures. The inferrer supplies a declared-
/// style effect for un-annotated callees at the call site. Declared effects
/// always win; inference is strictly a fallback.
@Suite
struct HeuristicInferenceTests: FrameworkAllowlistTestSupport {

    // MARK: - Non-idempotent name triggers

    @Test
    func bareInsert_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { insert(1) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareCreate_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { create() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareAppend_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { append(x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func memberInsert_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { db.insert(row) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    // MARK: - Destructive-verb allowlist (round-11 follow-on)
    //
    // Round 11 on Vapor surfaced `running.stop()` and `req.session.destroy()`
    // as missed catches — both short, unambiguous destructive verbs that
    // the existing allowlist didn't cover. Added to `nonIdempotentNames`.

    @Test
    func bareStop_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { stop() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func memberStop_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { running.stop() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func stopContainer_infersNonIdempotent_viaPrefix() throws {
        // Prefix match extends `stop` to camelCase-composed destructive
        // verbs like `stopContainer`, `stopService`, `stopTimer`.
        let call = try firstCall(in: "func f() { stopContainer() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareDestroy_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { destroy() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func memberDestroy_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { session.destroy() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func destroyResource_infersNonIdempotent_viaPrefix() throws {
        let call = try firstCall(in: "func f() { destroyResource(id) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func stopped_doesNotMatch_lowercaseNextCharacter() throws {
        // `stopped` is a past participle, not a mutation verb — camelCase
        // gate should block it (next character after `stop` is lowercase).
        let call = try firstCall(in: "func f() { stopped(task) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func destroyer_doesNotMatch_lowercaseNextCharacter() throws {
        // `destroyer` is a noun form; should not classify as non-idempotent.
        let call = try firstCall(in: "func f() { destroyer() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Server-app verbs (slot 13 — isowords round)
    //
    // The isowords round surfaced a real-bug miss on
    // `startDailyChallenge` (INSERT without `ON CONFLICT`) because
    // `start*` wasn't in the prefix list. `submit`, `start`,
    // `complete`, `register` are now bare + prefix-matched alongside
    // the original CRUD verbs. `send` was already there; these are
    // the four net additions.

    @Test
    func bareSubmit_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { submit(form) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func memberSubmit_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { form.submit() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func submitLeaderboardScore_infersNonIdempotent_viaPrefix() throws {
        // Isowords canonical case. Closure property on `DatabaseClient`
        // spelled `database.submitLeaderboardScore(...)`. Without this
        // prefix, Run A silently classified it as idempotent.
        let call = try firstCall(
            in: "func f() { database.submitLeaderboardScore(request) }"
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareStart_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { start() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func memberStart_infersNonIdempotent() throws {
        // `service.start()` — natural complement to `service.stop()`.
        let call = try firstCall(in: "func f() { service.start() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func startDailyChallenge_infersNonIdempotent_viaPrefix() throws {
        // The real-bug miss from the isowords round. SQL: INSERT
        // without ON CONFLICT against `dailyChallengePlays` — retry
        // creates a duplicate play row.
        let call = try firstCall(
            in: "func f() { database.startDailyChallenge(id, playerId) }"
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareComplete_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { complete() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func completeDailyChallenge_infersNonIdempotent_viaPrefix() throws {
        // Isowords state-transition write. SQL has a
        // `WHERE completedAt IS NULL` guard, so the catch is
        // defensible-by-design — but the prefix should still fire and
        // prompt the adopter to annotate `@lint.effect idempotent`.
        let call = try firstCall(
            in: "func f() { database.completeDailyChallenge(id, playerId) }"
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func bareRegister_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { register(token) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func registerPushToken_infersNonIdempotent_viaPrefix() throws {
        // Isowords `registerPushTokenMiddleware` calls. Defensible-by-
        // design via SNS idempotent ARN resolution + DB upsert, but
        // the prefix fires so the adopter can annotate.
        let call = try firstCall(
            in: "func f() { snsClient.registerPushToken(request) }"
        )
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    // Camel-case gate negative cases for the new verbs — confirm the
    // participle / noun forms stay silent.

    @Test
    func started_doesNotMatch_lowercaseNextCharacter() throws {
        // Past participle / past tense; not a mutation verb.
        let call = try firstCall(in: "func f() { started(service) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func submitted_doesNotMatch_lowercaseNextCharacter() throws {
        let call = try firstCall(in: "func f() { submitted(form) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func completion_doesNotMatch_lowercaseNextCharacter() throws {
        // Common callback-style noun form — `completion(result)`.
        let call = try firstCall(in: "func f() { completion(result) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func registered_doesNotMatch_lowercaseNextCharacter() throws {
        let call = try firstCall(in: "func f() { registered(device) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Idempotent name triggers

    @Test
    func bareUpsert_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { upsert(row) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .idempotent)
    }

    @Test
    func memberSetIfAbsent_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { cache.setIfAbsent(k, v) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .idempotent)
    }
}

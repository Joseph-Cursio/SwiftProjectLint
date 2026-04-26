import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Prefix-matching fixtures for the heuristic inferrer: verb prefixes,
/// camelCase gating on negative forms, and stdlib-receiver suppression.
@Suite
struct HeuristicInferencePrefixMatchingTests {

    // MARK: - Prefix matching (Phase 2 third slice — too-narrow fix)

    @Test
    func prefixSendEmail_infersNonIdempotent() throws {
        // The canonical R5 Run B case. `sendEmail` is a `send*` prefix
        // with an uppercase next character, no stdlib receiver — fires.
        let call = try firstCall(in: "func f() { sendEmail(to: x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixSendGiftEmail_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { sendGiftEmail(for: gift) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixCreateUser_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { createUser(name: \"a\") }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixInsertRow_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { insertRow(row) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixPublishEvent_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { publishEvent(event) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixAppendUnique_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { appendUnique(row) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixEnqueueJob_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { enqueueJob(job) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixPostMessage_infersNonIdempotent() throws {
        let call = try firstCall(in: "func f() { postMessage(m) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    @Test
    func prefixMemberCall_mailgunSendEmail_infersNonIdempotent() throws {
        // The other canonical R5 Run B case: `mailgun.sendEmail(...)`.
        // Receiver unresolved (mailgun is a global / property-wrapper
        // reference in real code) — the gate only silences on
        // `.stdlibCollection`, not `.unresolved`.
        let call = try memberCall(method: "sendEmail", in: "func f() { mailgun.sendEmail(x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == .nonIdempotent)
    }

    // MARK: - Prefix matching — camelCase gate (negative cases)

    @Test
    func sendingLowercaseNext_notMatched() throws {
        // `sending` is a participle, not a mutation verb. Lowercase next
        // character fails the camel-case gate.
        let call = try firstCall(in: "func f() { sending(x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func publisher_notMatched() throws {
        // Combine's `publisher(for:)` etc. — noun form, idempotent factory.
        let call = try firstCall(in: "func f() { publisher(for: x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func appending_notMatched() throws {
        // `NSString.appending`, `Array.appending` — functional form,
        // returns new value. Lowercase `i` fails the camel-case gate.
        let call = try firstCall(in: "func f() { appending(x) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func postponed_notMatched() throws {
        // Starts with `post` but the next character is lowercase.
        let call = try firstCall(in: "func f() { postponed(task) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func creator_notMatched() throws {
        let call = try firstCall(in: "func f() { creator() }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Prefix matching — stdlib gate

    @Test
    func prefixOnStringLiteralReceiver_suppressed() throws {
        // Even if a hypothetical `sendAsBytes()` method existed on String,
        // we don't fire on stdlib-collection receivers. Paranoid case —
        // the specific name probably isn't stdlib, but the gate is broad.
        let call = try memberCall(method: "sendAsBytes", in: #"func f() { "hello".sendAsBytes() }"#)
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func prefixOnArrayLiteralReceiver_suppressed() throws {
        // `Array.appending(_:)` exists — returns a new array, idempotent.
        // Prefix match `appendingX` on Array must stay silent.
        let call = try memberCall(method: "appending", in: "func f() { [1, 2].appending(3) }")
        #expect(HeuristicEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func prefixInferenceReason_emitted() throws {
        let call = try firstCall(in: "func f() { sendEmail(x) }")
        let reason = try #require(HeuristicEffectInferrer.inferenceReason(for: call))
        #expect(reason.contains("send"))
        #expect(reason.contains("sendEmail"))
        #expect(reason.contains("prefix"))
    }
}

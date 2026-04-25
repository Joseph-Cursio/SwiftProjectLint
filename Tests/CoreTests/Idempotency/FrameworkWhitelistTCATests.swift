import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// ComposableArchitecture (TCA) `send` closure-parameter override — when
/// `import ComposableArchitecture` is present, bare receiverless `send(...)`
/// calls inside TCA Effect closures classify as idempotent rather than
/// hitting the default non-idempotent bare-name lexicon. Split off from
/// `FrameworkWhitelistGatingTests` so the base struct stays under SwiftLint's
/// `type_body_length` threshold.
@Suite
struct FrameworkWhitelistTCATests {

    // MARK: - ComposableArchitecture (TCA) send-closure-parameter override

    @Test
    func importGated_tcaPresent_bareSendFiresIdempotent() throws {
        // `await send(.action)` inside a TCA Effect closure — the bare
        // `send` identifier is a `Send<Action>` closure parameter, and
        // calling it dispatches a pure state transition through the
        // reducer. With `import ComposableArchitecture` the override
        // beats the bare-name non-idempotent entry for `send`.
        let call = try firstCall(in: "func f() { send(.action) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["ComposableArchitecture"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_tcaAbsent_bareSendStaysNonIdempotent() throws {
        // No TCA import — `send(...)` hits the bare-name non-idempotent
        // list, which is the default posture for ambiguous `send` calls.
        let call = try firstCall(in: "func f() { send(.action) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func importGated_tcaPresent_receiverBasedSendStaysNonIdempotent() throws {
        // Receiver-based `mailer.send(.email)` in a TCA-importing file —
        // the override is receiverless-only. A user's mail-sending
        // helper should stay non-idempotent; only the closure-parameter
        // shape is exempted.
        let call = try firstCall(in: "func f() { mailer.send(.email) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["ComposableArchitecture"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func importGated_tcaPresent_sendEmailStillPrefixMatches() throws {
        // Exact-match only. `sendEmail(...)` still hits the
        // `matchesNonIdempotentPrefix` path for composed camelCase verbs.
        let call = try firstCall(in: "func f() { sendEmail(to: user) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["ComposableArchitecture"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func configGated_tcaDisabled_bareSendStaysNonIdempotent() throws {
        // Adopter imports ComposableArchitecture but opted out via
        // `enabled_framework_whitelists`. Override does not fire; the
        // bare-name non-idempotent list wins.
        let call = try firstCall(in: "func f() { send(.action) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["ComposableArchitecture"], enabledFrameworks: ["Foundation"]
        ) == .nonIdempotent)
    }

    @Test
    func tca_bareSend_inferenceReason_namesFramework() throws {
        let call = try firstCall(in: "func f() { send(.action) }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["ComposableArchitecture"], enabledFrameworks: nil
        )
        #expect(reason == "from the ComposableArchitecture closure-parameter primitive `send`")
    }
}

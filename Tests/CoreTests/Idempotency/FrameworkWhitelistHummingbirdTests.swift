import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Hummingbird-framework whitelist coverage: primitive pairs
/// (`HTTPError` / `request.decode` / `parameters.require`) and the
/// Router DSL whitelist (slot 16 — `router.get/post/put/patch/delete`).
/// Split off from `FrameworkWhitelistGatingTests` so the base struct
/// stays under SwiftLint's `type_body_length` threshold.
@Suite
struct FrameworkWhitelistHummingbirdTests {

    // MARK: - Hummingbird primitives (framework-gated)

    @Test
    func importGated_hummingbirdPresent_httpErrorFires() throws {
        let call = try firstCall(in: "func f() { _ = HTTPError(.notFound) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_hummingbirdAbsent_httpErrorDoesNotFire() throws {
        // A user-defined `HTTPError` type in a module without Hummingbird
        // shouldn't classify.
        let call = try firstCall(in: "func f() { _ = HTTPError(.notFound) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func importGated_hummingbirdPresent_requestDecodeFires() throws {
        let call = try firstCall(in: "func f() { try await request.decode(as: T.self) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_hummingbirdAbsent_requestDecodeDoesNotFire() throws {
        let call = try firstCall(in: "func f() { try await request.decode(as: T.self) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func importGated_hummingbirdPresent_parametersRequireFires() throws {
        // Chained receiver — callParts extracts "parameters" from
        // context.parameters.require(...) via the immediate-parent rule.
        let call = try firstCall(in: "func f() { try context.parameters.require(\"id\", as: UUID.self) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_hummingbirdAbsent_parametersRequireDoesNotFire() throws {
        let call = try firstCall(in: "func f() { try context.parameters.require(\"id\", as: UUID.self) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func hummingbirdPair_wrongReceiver_doesNotFire() throws {
        // `.decode()` on a non-`request` receiver in a Hummingbird-
        // importing file: should NOT match the Hummingbird pair (only
        // `request.decode` is whitelisted, not arbitrary `.decode()`).
        // Codec-receiver path handles `decoder.decode` etc. separately.
        let call = try firstCall(in: "func f() { try foo.decode(T.self) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func hummingbirdPair_wrongMethod_doesNotFire() throws {
        // `.wibble()` on `request` — method isn't in the pair table.
        let call = try firstCall(in: "func f() { request.wibble() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func configGated_hummingbirdDisabled_httpErrorDoesNotFire() throws {
        let call = try firstCall(in: "func f() { _ = HTTPError(.notFound) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: ["Foundation"]
        ) == nil)
    }

    @Test
    func hummingbird_httpError_inferenceReason() throws {
        let call = try firstCall(in: "func f() { _ = HTTPError(.notFound) }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["Hummingbird"], enabledFrameworks: nil
        )
        #expect(reason == "from the known-idempotent Hummingbird type `HTTPError`")
    }

    @Test
    func hummingbird_requestDecode_inferenceReason() throws {
        let call = try firstCall(in: "func f() { try request.decode(as: T.self) }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["Hummingbird"], enabledFrameworks: nil
        )
        #expect(reason == "from the Hummingbird primitive `request.decode`")
    }

    // MARK: - Hummingbird Router DSL whitelist (slot 16)

    @Test
    func importGated_hummingbirdPresent_routerGetFires() throws {
        // `router.get("/path") { ... }` — route-registration DSL inside
        // a `buildRouter()` / `addXRoutes(to router:)` helper. Without
        // this whitelist, strict mode would flag `get` as unannotated.
        let call = try firstCall(in: "func f() { router.get(\"/x\") { _, _ in \"\" } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_hummingbirdPresent_routerPostFires() throws {
        // `router.post` is the motivating slot-16 case — the callee
        // name `post` is in `nonIdempotentNames`, so without a receiver-
        // method whitelist ahead of the bare-name check, route
        // registration helpers annotated `@lint.context replayable`
        // would mis-fire on every `router.post(...)` DSL call.
        let call = try firstCall(in: "func f() { router.post(\"/x\") { _, _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_hummingbirdPresent_routerPutFires() throws {
        let call = try firstCall(in: "func f() { router.put(\"/x\") { _, _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_hummingbirdPresent_routerPatchFires() throws {
        let call = try firstCall(in: "func f() { router.patch(\"/x\") { _, _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_hummingbirdPresent_routerDeleteFires() throws {
        let call = try firstCall(in: "func f() { router.delete(\"/x\") { _, _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_hummingbirdAbsent_routerPostFiresAsNonIdempotent() throws {
        // Without Hummingbird, the slot-16 pair doesn't match and the
        // bare-name `post` classification at step 9 applies — the
        // whitelist is what silences the diagnostic, not a structural
        // override of the bare-name lexicon.
        let call = try firstCall(in: "func f() { router.post(\"/x\") { _, _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func importGated_hummingbirdAbsent_routerGetReturnsNil() throws {
        // `get` is in neither the bare-name idempotent nor non-idempotent
        // lists, so without the Hummingbird pair match the inferrer has
        // nothing to say — strict mode would surface it as unannotated.
        let call = try firstCall(in: "func f() { router.get(\"/x\") { _, _ in \"\" } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func hummingbirdRouterPair_wrongReceiver_doesNotSilenceBareName() throws {
        // `.post()` on a receiver other than `router` in a Hummingbird-
        // importing file: the slot-16 pair must not fire, and the bare-
        // name `post` lexicon path should still classify as non-idempotent.
        let call = try firstCall(in: "func f() { mailer.post(email) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func configGated_hummingbirdDisabled_routerPostFallsThroughToBareName() throws {
        // Adopter imports Hummingbird but opted out of its whitelist via
        // `enabled_framework_whitelists`. Slot-16 pair should not fire;
        // the bare-name `post` classification reasserts itself.
        let call = try firstCall(in: "func f() { router.post(\"/x\") { _, _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: ["Foundation"]
        ) == .nonIdempotent)
    }

    @Test
    func hummingbird_routerPost_inferenceReason() throws {
        let call = try firstCall(in: "func f() { router.post(\"/x\") { _, _ in } }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["Hummingbird"], enabledFrameworks: nil
        )
        #expect(reason == "from the Hummingbird primitive `router.post`")
    }

    @Test
    func hummingbirdRouterDelete_coexistsWithFluentDeleteClassification() throws {
        // Critical precedence test: `router.delete(...)` must classify
        // idempotent (slot-16 pair at step 5) even when FluentKit is
        // also imported — the receiver-method pair fires BEFORE the
        // framework-gated non-idempotent method path (step 11) where
        // Fluent's `delete` ORM verb lives.
        let routerCall = try firstCall(in: "func f() { router.delete(\"/x\") { _, _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: routerCall, imports: ["Hummingbird", "FluentKit"], enabledFrameworks: nil
        ) == .idempotent)

        // And in the same hypothetical file, `model.delete(on: db)` on
        // a non-`router` receiver must still hit Fluent's ORM-verb path
        // — the slot-16 entry is receiver-scoped to `router` only.
        let modelCall = try firstCall(in: "func f() { try await model.delete(on: db) }")
        #expect(HeuristicEffectInferrer.infer(
            call: modelCall, imports: ["Hummingbird", "FluentKit"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }
}

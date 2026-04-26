import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Vapor-framework whitelist coverage: routing DSL (slot 17 —
/// `app.get/post/put/patch/delete`) and `app.register(collection:)`
/// controller-mount idiom (slot 21). Split off from
/// `FrameworkWhitelistGatingTests` so the base struct stays under
/// SwiftLint's `type_body_length` threshold.
@Suite
struct FrameworkWhitelistVaporTests {

    // MARK: - Vapor routing DSL whitelist (slot 17)

    @Test
    func importGated_vaporPresent_appGetFires() throws {
        // `app.get("/path") { req in ... }` — Vapor inline-closure
        // route registration inside a `func routes(_ app:)` helper.
        // Silent under replayable via prefix-lexicon, but this entry
        // also covers strict_replayable where the prefix-lexicon path
        // doesn't short-circuit. 2-adopter evidence: luka-vapor +
        // HelloVapor.
        let call = try firstCall(in: "func f() { app.get(\"/x\") { _ in \"\" } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Vapor"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_vaporPresent_appPostFires() throws {
        // `app.post` is the motivating slot-17 case — `post` is in
        // `nonIdempotentNames`, so without the receiver-method pair
        // ahead of the bare-name check, every `app.post(...)` DSL
        // registration inside a `@lint.context replayable`-annotated
        // `routes(_:)` mis-fires.
        let call = try firstCall(in: "func f() { app.post(\"/x\") { _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Vapor"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_vaporPresent_appPutFires() throws {
        let call = try firstCall(in: "func f() { app.put(\"/x\") { _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Vapor"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_vaporPresent_appPatchFires() throws {
        let call = try firstCall(in: "func f() { app.patch(\"/x\") { _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Vapor"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_vaporPresent_appDeleteFires() throws {
        let call = try firstCall(in: "func f() { app.delete(\"/x\") { _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Vapor"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_vaporAbsent_appPostFiresAsNonIdempotent() throws {
        // Without Vapor, the slot-17 pair doesn't match and the bare-
        // name `post` classification at step 9 applies. A user-defined
        // `app` in a non-Vapor module shouldn't pick up the Vapor
        // classification just because the identifier matches.
        let call = try firstCall(in: "func f() { app.post(\"/x\") { _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func vaporAppPair_wrongReceiver_doesNotSilenceBareName() throws {
        // `.post()` on a receiver other than `app` in a Vapor-importing
        // file: the slot-17 pair must not fire, and the bare-name `post`
        // lexicon path should still classify as non-idempotent.
        let call = try firstCall(in: "func f() { mailer.post(email) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Vapor"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func configGated_vaporDisabled_appPostFallsThroughToBareName() throws {
        // Adopter imports Vapor but opted out of its whitelist via
        // `enabled_framework_whitelists`. Slot-17 pair should not fire;
        // the bare-name `post` classification reasserts itself.
        let call = try firstCall(in: "func f() { app.post(\"/x\") { _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Vapor"], enabledFrameworks: ["Foundation"]
        ) == .nonIdempotent)
    }

    @Test
    func vapor_appPost_inferenceReason() throws {
        let call = try firstCall(in: "func f() { app.post(\"/x\") { _ in } }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["Vapor"], enabledFrameworks: nil
        )
        #expect(reason == "from the Vapor primitive `app.post`")
    }

    @Test
    func vaporAppDelete_coexistsWithFluentDeleteClassification() throws {
        // Critical precedence test — Vapor adopters almost always import
        // Fluent too. `app.delete(...)` must classify idempotent (slot-17
        // pair at step 5) even when FluentKit is also imported, and
        // `model.delete(on: db)` on a non-`app` receiver must still hit
        // Fluent's ORM-verb path (step 11).
        let appCall = try firstCall(in: "func f() { app.delete(\"/x\") { _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: appCall, imports: ["Vapor", "FluentKit"], enabledFrameworks: nil
        ) == .idempotent)

        let modelCall = try firstCall(in: "func f() { try await model.delete(on: db) }")
        #expect(HeuristicEffectInferrer.infer(
            call: modelCall, imports: ["Vapor", "FluentKit"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func vaporAndHummingbirdImportedTogether_bothPairsActive() throws {
        // Multi-framework import — Vapor and Hummingbird co-imported.
        // Neither whitelist shadows the other; both `router.post` (slot 16)
        // and `app.post` (slot 17) resolve idempotent.
        let routerCall = try firstCall(in: "func f() { router.post(\"/x\") { _, _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: routerCall, imports: ["Vapor", "Hummingbird"], enabledFrameworks: nil
        ) == .idempotent)

        let appCall = try firstCall(in: "func f() { app.post(\"/x\") { _ in } }")
        #expect(HeuristicEffectInferrer.infer(
            call: appCall, imports: ["Vapor", "Hummingbird"], enabledFrameworks: nil
        ) == .idempotent)
    }

    // MARK: - Vapor `app.register(collection:)` whitelist (slot 21)

    @Test
    func importGated_vaporPresent_appRegisterCollectionFires() throws {
        // `app.register(collection: MyController())` — Vapor idiom for
        // mounting a `RouteCollection` conformer at startup time.
        // `register` is in `nonIdempotentNames` (slot 13 server-app verbs),
        // so without the slot-21 receiver-method pair ahead of the bare-
        // name check, every `app.register(collection:)` inside a
        // `@lint.context replayable`-annotated `routes(_:)` helper
        // mis-fires. 3-adopter evidence: HelloVapor + Uitsmijter +
        // plc-handle-tracker.
        let call = try firstCall(in: "func f() { try app.register(collection: FooController()) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Vapor"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_vaporAbsent_appRegisterFiresAsNonIdempotent() throws {
        // Without Vapor, the slot-21 pair doesn't match and the bare-
        // name `register` (slot 13) classification applies. A user-
        // defined `app` in a non-Vapor module shouldn't pick up the
        // Vapor classification just because the identifier matches.
        let call = try firstCall(in: "func f() { try app.register(collection: FooController()) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func vaporAppRegisterPair_wrongReceiver_doesNotSilenceBareName() throws {
        // `.register()` on a receiver other than `app` in a Vapor-
        // importing file: the slot-21 pair must not fire, and the bare-
        // name `register` lexicon path should still classify as
        // non-idempotent.
        let call = try firstCall(in: "func f() { registry.register(collection: FooController()) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Vapor"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func configGated_vaporDisabled_appRegisterFallsThroughToBareName() throws {
        // Adopter imports Vapor but opted out of its whitelist via
        // `enabled_framework_whitelists`. Slot-21 pair should not fire;
        // the bare-name `register` classification reasserts itself.
        let call = try firstCall(in: "func f() { try app.register(collection: FooController()) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Vapor"], enabledFrameworks: ["Foundation"]
        ) == .nonIdempotent)
    }

    @Test
    func vapor_appRegister_inferenceReason() throws {
        let call = try firstCall(in: "func f() { try app.register(collection: FooController()) }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["Vapor"], enabledFrameworks: nil
        )
        #expect(reason == "from the Vapor primitive `app.register`")
    }

    @Test
    func vaporAppRegister_coexistsWithFluentImport() throws {
        // Most Vapor adopters also import Fluent. slot-21's
        // `app.register(collection:)` must classify idempotent even
        // when FluentKit is also imported, and `model.register(...)`
        // on a non-`app` receiver (hypothetical user API) must not
        // be silenced by the slot-21 pair.
        let appCall = try firstCall(in: "func f() { try app.register(collection: FooController()) }")
        #expect(HeuristicEffectInferrer.infer(
            call: appCall, imports: ["Vapor", "FluentKit"], enabledFrameworks: nil
        ) == .idempotent)

        let modelCall = try firstCall(in: "func f() { try model.register(delegate) }")
        #expect(HeuristicEffectInferrer.infer(
            call: modelCall, imports: ["Vapor", "FluentKit"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }
}

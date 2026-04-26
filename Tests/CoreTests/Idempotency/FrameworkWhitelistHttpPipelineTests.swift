import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Slot 14 — the HttpPipeline pipeline-primitive whitelist. Covers the
/// freestanding curried functions (`writeStatus` / `respond`) used in
/// pointfreeco/swift-web's `conn |> writeStatus(.ok) >=> respond(html:)`
/// composition, plus the per-framework phrasing hook introduced with
/// this slot. Split off from `FrameworkWhitelistGatingTests` so the base
/// struct stays under SwiftLint's `type_body_length` threshold.
@Suite
struct FrameworkWhitelistHttpPipelineTests {

    // MARK: - HttpPipeline pipeline primitives (framework-gated, slot 14)

    @Test
    func importGated_httpPipelinePresent_writeStatusFires() throws {
        // `writeStatus` is a freestanding curried function in HttpPipeline
        // (`pointfreeco/swift-web`), typically called via
        // `conn |> writeStatus(.ok)` pipe-forward composition.
        // Each call is a value-typed `Conn` mutation; observably
        // idempotent at the response-builder boundary.
        let call = try firstCall(in: "func f() { _ = writeStatus(.ok) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["HttpPipeline"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_httpPipelineAbsent_writeStatusDoesNotFire() throws {
        // A user-defined `writeStatus(...)` in a module without
        // HttpPipeline shouldn't pick up the slot 14 classification
        // just because the identifier matches.
        let call = try firstCall(in: "func f() { _ = writeStatus(.ok) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func importGated_httpPipelinePresent_respondFires() throws {
        // `respond(html:)` / `respond(json:)` / `respond(text:)` —
        // curried response-builder primitive in HttpPipeline,
        // composed via `>=>` Kleisli.
        let call = try firstCall(in: "func f() { _ = respond(html: index) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["HttpPipeline"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_httpPipelineAbsent_respondDoesNotFire() throws {
        let call = try firstCall(in: "func f() { _ = respond(html: index) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func configGated_httpPipelineDisabled_writeStatusDoesNotFire() throws {
        // Adopter imports HttpPipeline but opted out via
        // `enabled_framework_whitelists`. Whitelist does not fire;
        // the un-classified callee remains `unknown`.
        let call = try firstCall(in: "func f() { _ = writeStatus(.ok) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["HttpPipeline"], enabledFrameworks: ["Foundation"]
        ) == nil)
    }

    @Test
    func httpPipeline_writeStatus_inferenceReason_namesFramework() throws {
        let call = try firstCall(in: "func f() { _ = writeStatus(.ok) }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["HttpPipeline"], enabledFrameworks: nil
        )
        #expect(reason == "from the HttpPipeline pipeline primitive `writeStatus`")
    }

    @Test
    func httpPipeline_respond_inferenceReason_namesFramework() throws {
        let call = try firstCall(in: "func f() { _ = respond(html: index) }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["HttpPipeline"], enabledFrameworks: nil
        )
        #expect(reason == "from the HttpPipeline pipeline primitive `respond`")
    }

    @Test
    func httpPipelineMethodPhrasing_hasOverride() {
        // Both per-framework phrasings on the slot 14 table should
        // resolve to their explicit overrides, not the generic default.
        #expect(FrameworkWhitelist.idempotentMethodPhrasing(forFramework: "FluentKit") == "query-builder read")
        #expect(FrameworkWhitelist.idempotentMethodPhrasing(forFramework: "HttpPipeline") == "pipeline primitive")
    }

    @Test
    func methodPhrasing_unknownFramework_fallsBackToGeneric() {
        // Slot 14 added a per-framework phrasing hook with a
        // `"framework primitive"` fallback — adding a new framework
        // to `idempotentMethodsByFramework` without specifying
        // phrasing should still produce a sensible reason string.
        #expect(FrameworkWhitelist.idempotentMethodPhrasing(forFramework: "PhantomFramework") == "framework primitive")
    }
}

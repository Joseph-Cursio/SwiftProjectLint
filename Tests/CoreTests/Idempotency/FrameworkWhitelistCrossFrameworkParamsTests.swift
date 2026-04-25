import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Slot 18 — the cross-framework `parameters.get` / `queryParameters.get`
/// table. These receivers show up under both Hummingbird and Vapor, so the
/// pair is gated on the multi-framework candidate set rather than a single
/// module. Split off from `FrameworkWhitelistGatingTests` so the base
/// struct stays under SwiftLint's `type_body_length` threshold.
@Suite
struct FrameworkWhitelistCrossFrameworkParamsTests {

    // MARK: - Cross-framework parameters.get / queryParameters.get (slot 18)

    @Test
    func slot18_parametersGet_firesUnderHummingbird() throws {
        // `context.parameters.get("id")` — Hummingbird URL parameter
        // retrieval. Cross-framework multi-framework table matches
        // because Hummingbird is in the candidate set.
        let call = try firstCall(in: "func f() { _ = parameters.get(\"id\") }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func slot18_parametersGet_firesUnderVapor() throws {
        // `req.parameters.get("name")` — Vapor URL parameter
        // retrieval. Same cross-framework entry as Hummingbird.
        let call = try firstCall(in: "func f() { _ = parameters.get(\"name\") }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Vapor"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func slot18_parametersGet_firesUnderBothFrameworksImported() throws {
        // Multi-import — both Hummingbird and Vapor imported. Cross-
        // framework table qualifies when at least one candidate is
        // active; having both active must not cause ambiguity.
        let call = try firstCall(in: "func f() { _ = parameters.get(\"id\") }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird", "Vapor"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func slot18_parametersGet_doesNotFireWithoutWebFramework() throws {
        // `parameters.get(...)` in a file that imports neither
        // Hummingbird nor Vapor must not match. The cross-framework
        // whitelist is the precision gate — without one of the listed
        // imports, a user-defined `parameters` variable stays unclassified.
        let call = try firstCall(in: "func f() { _ = parameters.get(\"id\") }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func slot18_queryParametersGet_firesUnderHummingbird() throws {
        // `request.uri.queryParameters.get(...)` — Hummingbird query-
        // parameter retrieval. Hummingbird-only; ships in the
        // single-framework table as a sibling to parameters.require.
        let call = try firstCall(in: "func f() { _ = queryParameters.get(\"page\") }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func slot18_queryParametersGet_doesNotFireUnderVaporOnly() throws {
        // `queryParameters` isn't a Vapor idiom — Vapor uses `req.query`
        // with a different accessor shape. Under Vapor-only imports,
        // the queryParameters.get entry must not match.
        let call = try firstCall(in: "func f() { _ = queryParameters.get(\"page\") }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Vapor"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func slot18_parametersGet_configGatedHummingbirdDisabled_stillFiresUnderVapor() throws {
        // Adopter imports both Hummingbird and Vapor but has disabled
        // Hummingbird's whitelist via config. Cross-framework table
        // still qualifies because Vapor (the other candidate) remains
        // active in `enabledFrameworks`.
        let call = try firstCall(in: "func f() { _ = parameters.get(\"id\") }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird", "Vapor"],
            enabledFrameworks: ["Vapor"]
        ) == .idempotent)
    }

    @Test
    func slot18_parametersGet_configGatedBothDisabled_doesNotFire() throws {
        // Both Hummingbird and Vapor disabled via config. Neither
        // candidate qualifies; cross-framework table doesn't match.
        let call = try firstCall(in: "func f() { _ = parameters.get(\"id\") }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird", "Vapor"],
            enabledFrameworks: ["Foundation"]
        ) == nil)
    }

    @Test
    func slot18_parametersGet_wrongReceiver_doesNotFire() throws {
        // A call with `foo.get(...)` receiver in a Hummingbird/Vapor
        // file must not be silenced — the cross-framework entry is
        // receiver-scoped to `parameters` only.
        let call = try firstCall(in: "func f() { _ = foo.get(\"id\") }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Hummingbird", "Vapor"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func slot18_parametersGet_inferenceReason_hummingbird() throws {
        let call = try firstCall(in: "func f() { _ = parameters.get(\"id\") }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["Hummingbird"], enabledFrameworks: nil
        )
        #expect(reason == "from the Hummingbird primitive `parameters.get`")
    }

    @Test
    func slot18_parametersGet_inferenceReason_vapor() throws {
        let call = try firstCall(in: "func f() { _ = parameters.get(\"id\") }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["Vapor"], enabledFrameworks: nil
        )
        #expect(reason == "from the Vapor primitive `parameters.get`")
    }
}

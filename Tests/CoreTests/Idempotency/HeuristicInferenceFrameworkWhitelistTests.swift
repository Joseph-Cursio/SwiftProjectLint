import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Framework-whitelist fixtures for the heuristic inferrer: known-pure
/// type constructors, `.init(...)` member-access form, codec-pattern
/// methods, and metric-pattern methods.
@Suite
struct HeuristicInferenceFrameworkWhitelistTests {

    // MARK: - Framework whitelist — idempotent type constructors
    //
    // Round-12 follow-on. Known-pure framework type constructors classify
    // idempotent when called as bare identifiers.

    @Test
    func jsonDecoderConstructor_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { _ = JSONDecoder() }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Foundation"]) == .idempotent)
    }

    @Test
    func jsonEncoderConstructor_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { _ = JSONEncoder() }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Foundation"]) == .idempotent)
    }

    @Test
    func dataConstructor_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { _ = Data(bytes) }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Foundation"]) == .idempotent)
    }

    @Test
    func byteBufferConstructor_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { _ = ByteBuffer(bytes: data) }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["NIOCore"]) == .idempotent)
    }

    @Test
    func albResponseConstructor_infersIdempotent() throws {
        let call = try firstCall(
            in: "func f() { _ = ALBTargetGroupResponse(statusCode: .ok) }"
        )
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["AWSLambdaEvents"]) == .idempotent)
    }

    @Test
    func uuidConstructor_staysUnclassified() throws {
        // DELIBERATELY EXCLUDED: UUID() produces a fresh-per-call identity.
        // Classifying it as idempotent would contradict the
        // `missingIdempotencyKey` rule this project specifically catches.
        let call = try firstCall(in: "func f() { _ = UUID() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func dateConstructor_staysUnclassified() throws {
        // DELIBERATELY EXCLUDED: Date() reads current time. Same call
        // produces different values across retries.
        let call = try firstCall(in: "func f() { _ = Date() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func userTypeConstructor_staysUnclassified() throws {
        // Project-local types aren't on the whitelist. Unclassified by
        // name alone; upward inference may still classify via body.
        let call = try firstCall(in: "func f() { _ = OrderService() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Framework whitelist — `.init(...)` member-access form
    //
    // The explicit-initializer form `JSONDecoder.init()` is semantically
    // identical to the bare `JSONDecoder()` — but without normalisation in
    // `callParts`, the member-access form would produce
    // `(calleeName: "init", receiverName: "JSONDecoder")` and miss the
    // type-constructor whitelist entirely. Adopter corpora surface the
    // `.init(...)` form at ~1 diagnostic per round on framework-response
    // builders. These fixtures pin the normalisation so the whitelist
    // fires on either spelling.

    @Test
    func jsonDecoderDotInit_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { _ = JSONDecoder.init() }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Foundation"]) == .idempotent)
    }

    @Test
    func dataDotInit_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { _ = Data.init(bytes) }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Foundation"]) == .idempotent)
    }

    @Test
    func albResponseDotInit_infersIdempotent() throws {
        // Framework-response-builder call-site shape — the motivating case
        // for normalising `.init(...)` to the bare-ctor path.
        let call = try firstCall(
            in: "func f() { _ = ALBTargetGroupResponse.init(statusCode: .ok) }"
        )
        #expect(
            CallSiteEffectInferrer.infer(call: call, imports: ["AWSLambdaEvents"])
                == .idempotent
        )
    }

    @Test
    func httpErrorDotInit_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { _ = HTTPError.init(.notFound) }")
        #expect(
            CallSiteEffectInferrer.infer(call: call, imports: ["Hummingbird"])
                == .idempotent
        )
    }

    @Test
    func genericTypeDotInit_infersIdempotent() throws {
        // `Data<T>` doesn't exist, but the generic-specialisation peel
        // applies uniformly — any whitelisted type invoked in the
        // `TypeName<...>.init(...)` shape normalises to the base name.
        // Use `ByteBuffer` with a fabricated generic for the AST shape.
        let call = try firstCall(in: "func f() { _ = ByteBuffer<UInt8>.init(bytes: data) }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["NIOCore"]) == .idempotent)
    }

    @Test
    func nestedTypeDotInit_picksLeafName() throws {
        // `Foo.APIGatewayV2Response.init(...)` — the nested form appears
        // when the response type is re-exported under a module namespace.
        // `callParts` returns the leaf type identifier, so the whitelist
        // lookup on `APIGatewayV2Response` still fires.
        let call = try firstCall(
            in: "func f() { _ = Outer.APIGatewayV2Response.init(statusCode: .ok) }"
        )
        #expect(
            CallSiteEffectInferrer.infer(call: call, imports: ["AWSLambdaEvents"])
                == .idempotent
        )
    }

    @Test
    func userTypeDotInit_staysUnclassified() throws {
        // `.init(...)` normalisation does NOT silence user-local types —
        // only types already on the framework whitelist benefit. A
        // project-local `OrderService.init()` remains unclassified, same
        // as the bare `OrderService()` form.
        let call = try firstCall(in: "func f() { _ = OrderService.init() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func uuidDotInit_staysUnclassified() throws {
        // Mirrors `uuidConstructor_staysUnclassified` — `UUID` is
        // deliberately excluded from the idempotent-type whitelist
        // because it produces a fresh-per-call identity. The
        // `.init(...)` form must not accidentally classify it either.
        let call = try firstCall(in: "func f() { _ = UUID.init() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func selfDotInit_staysUnclassified() throws {
        // Delegating initializer — `self.init(...)` is a convenience-init
        // dispatch, not a fresh construction. `"self"` isn't on any
        // whitelist, so the normalisation returns no inferred effect,
        // matching pre-slice behaviour exactly.
        let call = try firstCall(
            in: "struct S { init() { self.init(default: true) } }"
        )
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func jsonDecoderDotInit_reasonMatchesBareForm() throws {
        // Inference reason credits the whitelisted type, not "init",
        // so adopter diagnostics read coherently on both spellings.
        let call = try firstCall(in: "func f() { _ = JSONDecoder.init() }")
        let reason = CallSiteEffectInferrer.inferenceReason(
            for: call,
            imports: ["Foundation"]
        )
        #expect(reason == "from the known-idempotent Foundation type `JSONDecoder`")
    }

    // MARK: - Framework whitelist — codec-pattern methods

    @Test
    func decoderDotDecode_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { decoder.decode(T.self, from: data) }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Foundation"]) == .idempotent)
    }

    @Test
    func encoderDotEncode_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { encoder.encode(value) }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Foundation"]) == .idempotent)
    }

    @Test
    func jsonDecoderStyleReceiver_infersIdempotent() throws {
        let call = try firstCall(in: "func f() { jsonDecoder.decode(T.self, from: data) }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Foundation"]) == .idempotent)
    }

    @Test
    func decodeOnNonCodecReceiver_staysUnclassified() throws {
        // Vapor's `req.content.decode(...)` — receiver `content` doesn't
        // contain `decoder`/`encoder`. The codec-pattern heuristic doesn't
        // fire here; the 5-hop upward inference round-11 observed still
        // applies.
        let call = try firstCall(in: "func f() { content.decode(Creds.self) }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    // MARK: - Framework whitelist — metric-pattern methods

    @Test
    func counterIncrement_infersObservational() throws {
        let call = try firstCall(in: "func f() { counter.increment() }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Metrics"]) == .observational)
    }

    @Test
    func meterDecrement_infersObservational() throws {
        let call = try firstCall(in: "func f() { activeRequestMeter.decrement() }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Metrics"]) == .observational)
    }

    @Test
    func timerRecordNanoseconds_infersObservational() throws {
        let call = try firstCall(in: "func f() { timer.recordNanoseconds(100) }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Metrics"]) == .observational)
    }

    @Test
    func gaugeRecord_infersObservational() throws {
        let call = try firstCall(in: "func f() { gauge.record(42.0) }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Metrics"]) == .observational)
    }

    @Test
    func metricMethodOnNonMetricReceiver_staysUnclassified() throws {
        // `view.record()` — the method is a metric-observation verb but the
        // receiver isn't metric-shaped. Don't fire.
        let call = try firstCall(in: "func f() { view.record() }")
        #expect(CallSiteEffectInferrer.infer(call: call) == nil)
    }

    @Test
    func chainedMetricReceiver_infersObservational() throws {
        // `context.metrics.counter.increment()` — immediate-parent segment
        // is `counter`, which matches the metric-receiver shape.
        let call = try firstCall(in: "func f() { context.metrics.counter.increment() }")
        #expect(CallSiteEffectInferrer.infer(call: call, imports: ["Metrics"]) == .observational)
    }
}

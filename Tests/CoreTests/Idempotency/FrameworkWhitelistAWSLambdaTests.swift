import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// AWSLambdaRuntime-framework whitelist coverage: the response-writer
/// primitive pairs (`outputWriter.write` / `responseWriter.write` /
/// `responseWriter.finish`) for both the buffered and streaming
/// swift-aws-lambda-runtime v2.x handler shapes. Split off from
/// `FrameworkWhitelistGatingTests` so the base struct stays under
/// SwiftLint's `type_body_length` threshold.
@Suite
struct FrameworkWhitelistAWSLambdaTests {

    // MARK: - AWSLambdaRuntime response-writer primitives (framework-gated)

    @Test
    func importGated_lambdaRuntimePresent_outputWriterWriteFires() throws {
        // `outputWriter.write(...)` in a `LambdaWithBackgroundProcessingHandler`.
        // The closure-parameter receiver name is canonical in the
        // swift-aws-lambda-runtime v2.x signature. Idempotent-in-replay
        // per the Lambda at-least-once contract (dedup at invocation
        // boundary, not per-call).
        let call = try firstCall(in: "func f() { try await outputWriter.write(greeting) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["AWSLambdaRuntime"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_lambdaRuntimeAbsent_outputWriterWriteDoesNotFire() throws {
        // A user-defined `outputWriter` in a module without AWSLambdaRuntime
        // shouldn't pick up the Lambda classification just because the
        // identifier matches.
        let call = try firstCall(in: "func f() { try await outputWriter.write(greeting) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func importGated_lambdaRuntimePresent_responseWriterWriteFires() throws {
        // Streaming shape — `responseWriter.write(...)` on
        // `LambdaResponseStreamWriter`.
        let call = try firstCall(in: "func f() { try await responseWriter.write(buffer) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["AWSLambdaRuntime"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_lambdaRuntimePresent_responseWriterFinishFires() throws {
        // Streaming stream-close — `responseWriter.finish()`.
        let call = try firstCall(in: "func f() { try await responseWriter.finish() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["AWSLambdaRuntime"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_lambdaRuntimeAbsent_responseWriterFinishDoesNotFire() throws {
        let call = try firstCall(in: "func f() { try await responseWriter.finish() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func lambdaRuntimePair_wrongReceiver_writeDoesNotFire() throws {
        // `.write()` on a non-`outputWriter`/`responseWriter` receiver
        // in an AWSLambdaRuntime-importing file: should NOT match the
        // Lambda pair. Only the canonical runtime-callback receiver
        // names are whitelisted; arbitrary `.write()` (e.g. file-handle
        // writes) keeps its unclassified status.
        let call = try firstCall(in: "func f() { try fileHandle.write(data) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["AWSLambdaRuntime"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func lambdaRuntimePair_wrongReceiver_finishDoesNotFire() throws {
        // `.finish()` on a non-`responseWriter` receiver — not in the
        // pair table even with AWSLambdaRuntime imported.
        let call = try firstCall(in: "func f() { animation.finish() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["AWSLambdaRuntime"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func lambdaRuntimePair_wrongMethod_doesNotFire() throws {
        // `.wibble()` on `responseWriter` — method isn't in the pair
        // table. Confirms lookup is pair-keyed, not receiver-only.
        let call = try firstCall(in: "func f() { responseWriter.wibble() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["AWSLambdaRuntime"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func configGated_lambdaRuntimeDisabled_writeDoesNotFire() throws {
        // Adopter has AWSLambdaRuntime imported but opted out of the
        // whitelist via .swiftprojectlint.yml.
        let call = try firstCall(in: "func f() { try await outputWriter.write(greeting) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["AWSLambdaRuntime"], enabledFrameworks: ["Foundation"]
        ) == nil)
    }

    @Test
    func lambdaRuntime_outputWriterWrite_inferenceReason() throws {
        let call = try firstCall(in: "func f() { try await outputWriter.write(greeting) }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["AWSLambdaRuntime"], enabledFrameworks: nil
        )
        #expect(reason == "from the AWSLambdaRuntime primitive `outputWriter.write`")
    }

    @Test
    func lambdaRuntime_responseWriterFinish_inferenceReason() throws {
        let call = try firstCall(in: "func f() { try await responseWriter.finish() }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["AWSLambdaRuntime"], enabledFrameworks: nil
        )
        #expect(reason == "from the AWSLambdaRuntime primitive `responseWriter.finish`")
    }
}

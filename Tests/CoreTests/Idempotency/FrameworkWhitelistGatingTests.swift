import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Covers the `infer(call:imports:enabledFrameworks:)` API along two axes:
///   1. Import-gated — a framework's whitelist fires only when the
///      `imports` set contains the framework's base module name.
///      Absent module = silent (modulo un-gated paths like the logger
///      receiver heuristic).
///   2. Config-gated — `enabledFrameworks` non-nil restricts the active
///      whitelist set even when imports would otherwise allow more.
@Suite
struct FrameworkWhitelistGatingTests {

    // MARK: - Empty imports (no framework gates fire)

    @Test
    func emptyImports_jsonDecoderDoesNotFire() throws {
        // An empty imports set means "no framework-gated whitelist is
        // active" — synthetic fixtures and files without imports behave
        // identically. Foundation's JSONDecoder stays unclassified.
        let call = try firstCall(in: "func f() { _ = JSONDecoder() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: [], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func emptyImports_bareNameStillFires() throws {
        // Bare-name whitelist (`create`/`insert`/etc.) is un-gated, so
        // even with no imports the heuristic still classifies.
        let call = try firstCall(in: "func f() { insert(row) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: [], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func emptyImports_loggerStillFires() throws {
        // The logger receiver-shape heuristic is intentionally un-gated
        // (see `HeuristicEffectInferrer.loggerPattern` discussion).
        let call = try firstCall(in: "func f() { logger.info(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: [], enabledFrameworks: nil
        ) == .observational)
    }

    // MARK: - Import-gated (non-empty imports)

    @Test
    func importGated_foundationPresent_jsonDecoderFires() throws {
        let call = try firstCall(in: "func f() { _ = JSONDecoder() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Foundation"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_foundationAbsent_jsonDecoderDoesNotFire() throws {
        // Explicit non-empty imports without Foundation — the file is
        // a known module context but doesn't import Foundation, so
        // user-defined `JSONDecoder` should not classify.
        let call = try firstCall(in: "func f() { _ = JSONDecoder() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func importGated_nioPresent_byteBufferFires() throws {
        let call = try firstCall(in: "func f() { _ = ByteBuffer(bytes: data) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["NIOCore"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_nioAbsent_byteBufferDoesNotFire() throws {
        let call = try firstCall(in: "func f() { _ = ByteBuffer(bytes: data) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Foundation"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func loggerPattern_isHighPrecision_firesRegardlessOfImports() throws {
        // The logger pattern is intentionally NOT import-gated. The
        // receiver-shape + level-method dual signal is high-precision,
        // and swift-log is commonly accessed through framework-provided
        // properties (`context.logger`, `request.logger`) where the
        // file's own imports don't include `Logging`. Gating on
        // `Logging`/`os` regressed round-9's chained-logger fix on the
        // Lambda corpus in early round-14 testing — un-gated.
        let call = try firstCall(in: "func f() { logger.info(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Logging"], enabledFrameworks: nil
        ) == .observational)
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["AWSLambdaRuntime"], enabledFrameworks: nil
        ) == .observational)
        // Also fires with no Logging-related import — adopters with
        // user-defined loggers can override via explicit annotation.
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == .observational)
    }

    @Test
    func importGated_metricsPresent_counterIncrementFires() throws {
        let call = try firstCall(in: "func f() { counter.increment() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Metrics"], enabledFrameworks: nil
        ) == .observational)
    }

    @Test
    func importGated_metricsAbsent_counterIncrementDoesNotFire() throws {
        // The classic round-13 false-positive: user-defined `Counter` in
        // a project without `import Metrics` shouldn't classify as
        // observational just because the receiver name matches.
        let call = try firstCall(in: "func f() { counter.increment() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func importGated_codecPattern_requiresFoundation() throws {
        let call = try firstCall(in: "func f() { decoder.decode(T.self, from: data) }")
        // Codec pattern requires Foundation for the Codable protocols.
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Foundation"], enabledFrameworks: nil
        ) == .idempotent)
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    // MARK: - Config-gated (enabledFrameworks non-nil)

    @Test
    func configGated_foundationDisabled_jsonDecoderDoesNotFire() throws {
        // Foundation imported AND the type matches, but the project
        // has set enabledFrameworks to exclude Foundation.
        let call = try firstCall(in: "func f() { _ = JSONDecoder() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Foundation"], enabledFrameworks: ["NIOCore"]
        ) == nil)
    }

    @Test
    func configGated_loggerStillFires_logging_isUngated() throws {
        // Mirrors `loggerPattern_isHighPrecision_firesRegardlessOfImports`:
        // the logger pattern bypasses both the import gate and the
        // config gate, so adopters who want to silence it must
        // annotate the callee explicitly rather than disable the
        // framework whitelist.
        let call = try firstCall(in: "func f() { logger.info(\"x\") }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Logging"], enabledFrameworks: ["Foundation"]
        ) == .observational)
    }

    @Test
    func configGated_emptyEnabledSet_disablesAllFrameworks() throws {
        let call = try firstCall(in: "func f() { _ = JSONDecoder() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["Foundation"], enabledFrameworks: []
        ) == nil)
    }
}

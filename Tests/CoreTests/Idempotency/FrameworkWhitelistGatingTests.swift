import Testing
@testable import Core
@testable import SwiftProjectLintRules
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

    private func firstCall(in source: String) throws -> FunctionCallExprSyntax {
        final class Finder: SyntaxVisitor {
            var call: FunctionCallExprSyntax?
            init() { super.init(viewMode: .sourceAccurate) }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if call == nil { call = node }
                return .skipChildren
            }
        }
        let finder = Finder()
        finder.walk(Parser.parse(source: source))
        return try #require(finder.call)
    }

    /// Locates a specific member-access call by method name in a source
    /// snippet. Needed to pick the terminal `.all()` / `.first()` etc.
    /// out of a chained expression where `firstCall` would return the
    /// outer-most call.
    private func memberCall(method: String, in source: String) throws -> FunctionCallExprSyntax {
        final class Finder: SyntaxVisitor {
            let method: String
            var call: FunctionCallExprSyntax?
            init(method: String) {
                self.method = method
                super.init(viewMode: .sourceAccurate)
            }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if call == nil,
                   let member = node.calledExpression.as(MemberAccessExprSyntax.self),
                   member.declName.baseName.text == method {
                    call = node
                }
                return .visitChildren
            }
        }
        let finder = Finder(method: method)
        finder.walk(Parser.parse(source: source))
        return try #require(finder.call, "expected a call to .\(method)")
    }

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

    // MARK: - Fluent non-idempotent verbs (framework-gated, receiver-only)

    @Test
    func importGated_fluentPresent_modelSaveFires() throws {
        let call = try firstCall(in: "func f() { todo.save() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func importGated_fluentPresent_modelUpdateFires() throws {
        let call = try firstCall(in: "func f() { todo.update() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func importGated_fluentPresent_modelDeleteFires() throws {
        let call = try firstCall(in: "func f() { todo.delete() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func importGated_fluentAbsent_modelSaveDoesNotFire() throws {
        // The classic false-positive the gate prevents: a cache with a
        // `save(key:value:)` method shouldn't classify as non-idempotent
        // just because the verb matches Fluent.
        let call = try firstCall(in: "func f() { cache.save() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func importGated_fluentAbsent_setUpdateDoesNotFire() throws {
        // stdlib `Set.update(with:)` must not classify as Fluent's
        // non-idempotent `update` on an adopter that doesn't import FluentKit.
        let call = try firstCall(in: "func f() { var s: Set<Int> = []; s.update(with: 1) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func fluent_bareSaveCall_doesNotFire() throws {
        // No receiver = top-level free function, structurally unrelated
        // to Fluent. Fluent's verbs are always called on a Model-conforming
        // instance.
        let call = try firstCall(in: "func f() { save() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func configGated_fluentDisabled_modelSaveDoesNotFire() throws {
        // Adopter has FluentKit imported but opted out of Fluent
        // classifications in their .swiftprojectlint.yml.
        let call = try firstCall(in: "func f() { todo.save() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: ["Foundation"]
        ) == nil)
    }

    @Test
    func fluent_inferenceReason_namesFramework() throws {
        let call = try firstCall(in: "func f() { todo.save() }")
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["FluentKit"], enabledFrameworks: nil
        )
        #expect(reason == "from the FluentKit ORM verb `save`")
    }

    // MARK: - Fluent query-builder idempotent reads (framework-gated)

    @Test
    func importGated_fluentPresent_queryFires() throws {
        let call = try firstCall(in: "func f() { Todo.query(on: db) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_fluentPresent_allFires_onChainedCall() throws {
        // Critical shape: `Todo.query(on: db).all()` — the terminal
        // `.all()` has no simple receiver identifier (its base is a
        // FunctionCallExpr, not a DeclRefExpr). The idempotent gate
        // must fire without a receiver binding.
        let source = "func f() { _ = Todo.query(on: db).all() }"
        let call = try memberCall(method: "all", in: source)
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_fluentPresent_firstFires_onChainedCall() throws {
        let source = "func f() { _ = Todo.query(on: db).filter(x).first() }"
        let call = try memberCall(method: "first", in: source)
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_fluentPresent_filterFires_onChainedCall() throws {
        let source = "func f() { _ = Todo.query(on: db).filter(x).all() }"
        let call = try memberCall(method: "filter", in: source)
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_fluentPresent_dbFires() throws {
        let call = try firstCall(in: "func f() { fluent.db() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_fluentAbsent_queryDoesNotFire() throws {
        // User-defined `.query()` in a module without FluentKit —
        // classification is not Fluent's business.
        let call = try firstCall(in: "func f() { db.query(on: x) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func configGated_fluentDisabled_queryDoesNotFire() throws {
        let call = try firstCall(in: "func f() { Todo.query(on: db) }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: ["Foundation"]
        ) == nil)
    }

    @Test
    func fluentIdempotent_inferenceReason_namesFramework() throws {
        let source = "func f() { _ = Todo.query(on: db).all() }"
        let call = try memberCall(method: "all", in: source)
        let reason = HeuristicEffectInferrer.inferenceReason(
            for: call, imports: ["FluentKit"], enabledFrameworks: nil
        )
        #expect(reason == "from the FluentKit query-builder read `all`")
    }

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

    // MARK: - ImportCollector

    @Test
    func importCollector_extractsTopLevelImports() {
        let source: SourceFileSyntax = Parser.parse(source: """
        import Foundation
        import NIOCore
        @preconcurrency import Logging
        """)
        let imports = ImportCollector.imports(in: source)
        #expect(imports == ["Foundation", "NIOCore", "Logging"])
    }

    @Test
    func importCollector_handlesSubmoduleImports() {
        let source: SourceFileSyntax = Parser.parse(source: """
        import class Foundation.JSONDecoder
        import NIOCore.ByteBuffer
        """)
        let imports = ImportCollector.imports(in: source)
        // Base-module names only; submodule paths collapse.
        #expect(imports == ["Foundation", "NIOCore"])
    }

    @Test
    func importCollector_emptyForNoImports() {
        let source: SourceFileSyntax = Parser.parse(source: """
        func foo() {}
        """)
        let imports = ImportCollector.imports(in: source)
        #expect(imports.isEmpty)
    }
}

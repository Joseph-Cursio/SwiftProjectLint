import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Round-14 follow-on coverage. Exercises the new
/// `infer(call:imports:enabledFrameworks:)` API along three axes:
///   1. Backward-compat — `imports = nil` matches every framework
///      (preserves test fixtures that don't declare imports).
///   2. Import-gated — explicit non-empty imports only fire matching
///      frameworks' whitelists.
///   3. Config-gated — `enabledFrameworks` non-nil restricts the active
///      whitelist set even when imports would allow more.
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

    // MARK: - Backward compatibility (imports = nil)

    @Test
    func backwardCompat_importsNil_jsonDecoderClassifiesIdempotent() throws {
        let call = try firstCall(in: "func f() { _ = JSONDecoder() }")
        // Old call site (and existing tests) expect this to fire.
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: nil, enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func backwardCompat_importsEmpty_jsonDecoderStillClassifiesIdempotent() throws {
        // Empty imports = "synthetic fixture, no module signal" — falls
        // back to the always-active behaviour. Round-14 design choice
        // documented in `FrameworkContext`.
        let call = try firstCall(in: "func f() { _ = JSONDecoder() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: [], enabledFrameworks: nil
        ) == .idempotent)
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
    func backwardCompat_importsNil_modelSaveFires() throws {
        // nil imports = backward-compat mode where every framework is active.
        let call = try firstCall(in: "func f() { todo.save() }")
        #expect(HeuristicEffectInferrer.infer(
            call: call, imports: nil, enabledFrameworks: nil
        ) == .nonIdempotent)
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

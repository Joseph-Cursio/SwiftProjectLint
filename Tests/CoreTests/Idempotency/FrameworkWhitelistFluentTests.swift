import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Fluent-framework whitelist coverage: non-idempotent ORM verbs,
/// idempotent query-builder reads, and the `Fluent` meta-package import
/// alias (slot 19). Split off from `FrameworkWhitelistGatingTests` so the
/// base struct stays under SwiftLint's `type_body_length` threshold.
@Suite
struct FrameworkWhitelistFluentTests {

    // MARK: - Fluent non-idempotent verbs (framework-gated, receiver-only)

    @Test
    func importGated_fluentPresent_modelSaveFires() throws {
        let call = try firstCall(in: "func f() { todo.save() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func importGated_fluentPresent_modelUpdateFires() throws {
        let call = try firstCall(in: "func f() { todo.update() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func importGated_fluentPresent_modelDeleteFires() throws {
        let call = try firstCall(in: "func f() { todo.delete() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func importGated_fluentAbsent_modelSaveDoesNotFire() throws {
        // The classic false-positive the gate prevents: a cache with a
        // `save(key:value:)` method shouldn't classify as non-idempotent
        // just because the verb matches Fluent.
        let call = try firstCall(in: "func f() { cache.save() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func importGated_fluentAbsent_setUpdateDoesNotFire() throws {
        // stdlib `Set.update(with:)` must not classify as Fluent's
        // non-idempotent `update` on an adopter that doesn't import FluentKit.
        let call = try firstCall(in: "func f() { var s: Set<Int> = []; s.update(with: 1) }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func fluent_bareSaveCall_doesNotFire() throws {
        // No receiver = top-level free function, structurally unrelated
        // to Fluent. Fluent's verbs are always called on a Model-conforming
        // instance.
        let call = try firstCall(in: "func f() { save() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func configGated_fluentDisabled_modelSaveDoesNotFire() throws {
        // Adopter has FluentKit imported but opted out of Fluent
        // classifications in their .swiftprojectlint.yml.
        let call = try firstCall(in: "func f() { todo.save() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: ["Foundation"]
        ) == nil)
    }

    @Test
    func fluent_inferenceReason_namesFramework() throws {
        let call = try firstCall(in: "func f() { todo.save() }")
        let reason = CallSiteEffectInferrer.inferenceReason(
            for: call, imports: ["FluentKit"], enabledFrameworks: nil
        )
        #expect(reason == "from the FluentKit ORM verb `save`")
    }

    // MARK: - Fluent query-builder idempotent reads (framework-gated)

    @Test
    func importGated_fluentPresent_queryFires() throws {
        let call = try firstCall(in: "func f() { Todo.query(on: db) }")
        #expect(CallSiteEffectInferrer.infer(
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
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_fluentPresent_firstFires_onChainedCall() throws {
        let source = "func f() { _ = Todo.query(on: db).filter(x).first() }"
        let call = try memberCall(method: "first", in: source)
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_fluentPresent_filterFires_onChainedCall() throws {
        let source = "func f() { _ = Todo.query(on: db).filter(x).all() }"
        let call = try memberCall(method: "filter", in: source)
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_fluentPresent_dbFires() throws {
        let call = try firstCall(in: "func f() { fluent.db() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_fluentAbsent_queryDoesNotFire() throws {
        // User-defined `.query()` in a module without FluentKit —
        // classification is not Fluent's business.
        let call = try firstCall(in: "func f() { db.query(on: x) }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["MyApp"], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func configGated_fluentDisabled_queryDoesNotFire() throws {
        let call = try firstCall(in: "func f() { Todo.query(on: db) }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["FluentKit"], enabledFrameworks: ["Foundation"]
        ) == nil)
    }

    @Test
    func fluentIdempotent_inferenceReason_namesFramework() throws {
        let source = "func f() { _ = Todo.query(on: db).all() }"
        let call = try memberCall(method: "all", in: source)
        let reason = CallSiteEffectInferrer.inferenceReason(
            for: call, imports: ["FluentKit"], enabledFrameworks: nil
        )
        #expect(reason == "from the FluentKit query-builder read `all`")
    }

    // MARK: - Fluent import alias (slot 19)

    /// Slot 19 — the `Fluent` meta-package (`vapor/fluent`) re-exports
    /// `FluentKit`, so idiomatic Vapor code imports `Fluent` and the gate
    /// must treat that as equivalent to `FluentKit`. Mirrors the Fluent
    /// sections above with `imports: ["Fluent"]` in place of
    /// `["FluentKit"]`. Evidence from the hellovapor package trial — a
    /// `save(on:)` call under `import Fluent` went silent until the gate
    /// was aliased.

    @Test
    func importGated_fluentMetaPackage_modelSaveFires() throws {
        let call = try firstCall(in: "func f() { todo.save() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["Fluent"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func importGated_fluentMetaPackage_modelUpdateFires() throws {
        let call = try firstCall(in: "func f() { todo.update() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["Fluent"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func importGated_fluentMetaPackage_modelDeleteFires() throws {
        let call = try firstCall(in: "func f() { todo.delete() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["Fluent"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func importGated_fluentMetaPackage_queryFires() throws {
        let call = try firstCall(in: "func f() { Todo.query(on: db) }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["Fluent"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func importGated_fluentMetaPackage_allFires_onChainedCall() throws {
        // Same shape as the FluentKit chained-read test — the terminal
        // `.all()` on a query builder resolves through the idempotent
        // method gate when the file imports the meta-package.
        let source = "func f() { _ = Todo.query(on: db).all() }"
        let call = try memberCall(method: "all", in: source)
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["Fluent"], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func fluentMetaPackage_inferenceReason_usesCanonicalFrameworkName() throws {
        // The alias gates import presence; the reason string keeps the
        // canonical `FluentKit` name so users searching the docs for the
        // rule reason see the same phrasing regardless of import spelling.
        let call = try firstCall(in: "func f() { todo.save() }")
        let reason = CallSiteEffectInferrer.inferenceReason(
            for: call, imports: ["Fluent"], enabledFrameworks: nil
        )
        #expect(reason == "from the FluentKit ORM verb `save`")
    }

    @Test
    func fluentMetaPackage_idempotentReadReason_usesCanonicalFrameworkName() throws {
        let source = "func f() { _ = Todo.query(on: db).all() }"
        let call = try memberCall(method: "all", in: source)
        let reason = CallSiteEffectInferrer.inferenceReason(
            for: call, imports: ["Fluent"], enabledFrameworks: nil
        )
        #expect(reason == "from the FluentKit query-builder read `all`")
    }

    @Test
    func fluentBothImports_modelSaveFires() throws {
        // Redundant but legal — some adopters import both the
        // meta-package and the concrete module. Either alone activates
        // the gate, and both together should behave identically.
        let call = try firstCall(in: "func f() { todo.save() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["Fluent", "FluentKit"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func configGated_fluentDisabled_metaPackageAliasStillSilenced() throws {
        // `enabledFrameworks` gates by the canonical name, not by the
        // import spelling. An adopter opting out of Fluent via config
        // stays silenced under `import Fluent` just as under
        // `import FluentKit` — the alias is purely an import-gate
        // convenience.
        let call = try firstCall(in: "func f() { todo.save() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["Fluent"], enabledFrameworks: ["Foundation"]
        ) == nil)
    }

    @Test
    func fluentMetaPackage_nonAliasNameDoesNotActivateGate() throws {
        // Defensive: only the enumerated alias `Fluent` qualifies.
        // A user-defined module whose name merely prefixes `Fluent`
        // (e.g. `MyFluentHelpers`) must not activate the gate.
        let call = try firstCall(in: "func f() { todo.save() }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: ["MyFluentHelpers"], enabledFrameworks: nil
        ) == nil)
    }
}

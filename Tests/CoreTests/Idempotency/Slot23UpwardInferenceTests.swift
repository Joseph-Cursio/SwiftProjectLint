import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Tests the slot-23 fix: upward inference must populate `upwardInferredEffects`
/// even when the signature already has a context-only entry in
/// `entriesBySignature`. The pre-fix guard `entriesBySignature[sig] == nil`
/// silently dropped upward inference for `@lint.context replayable`-annotated
/// sub-handlers, producing the silent miss seen on tinyfaces (round 17) and
/// unidoc (round 18) when a switch dispatcher's `@lint.context replayable`
/// annotation called into context-only-annotated sub-handlers.
@Suite
struct Slot23UpwardInferenceTests {

    @Test func contextOnlyAnnotated_getsUpwardInference_forNonIdempotentBody() {
        // A function annotated with @lint.context replayable but no
        // @lint.effect should still have its body's effect upward-inferred
        // and stored, so callers can see it.
        let source = """
        /// @lint.context replayable
        func subHandler() async throws {
            try await db.users.update("x")
        }
        """
        var table = EffectSymbolTable()
        let parsed = Parser.parse(source: source)
        table.merge(source: parsed)

        // Sanity: entry exists with context but no effect.
        let signature = FunctionSignature(name: "subHandler", argumentLabels: [])
        #expect(table.effect(for: signature) == nil,
                "no declared effect (context-only)")
        #expect(table.context(for: signature) == .replayable,
                "context is recorded")

        // Run upward inference. With multiHop, the sub-handler's
        // body-inferred non-idempotent should land in upwardInferredEffects.
        table.applyUpwardInferenceImportAware(
            to: [parsed],
            multiHop: true
        ) { call, _ in
            // Heuristic: any call to `update` is non-idempotent.
            if let sig = FunctionSignature.from(call: call), sig.name == "update" {
                return .nonIdempotent
            }
            return nil
        }

        let upward = table.upwardInference(for: signature)
        #expect(upward?.effect == .nonIdempotent)
    }

    @Test func dispatcher_seesSubHandler_viaUpwardInference_throughSwitchCase() {
        // The end-to-end slot-23 shape: a context-annotated dispatcher
        // whose body switches into context-annotated sub-handlers should
        // see the sub-handlers as non-idempotent via upward inference,
        // letting the dispatcher itself be inferred non-idempotent.
        let source = """
        enum Event { case installation(Int), createSomething(Int) }

        /// @lint.context replayable
        func dispatch(event: Event) async throws {
            switch event {
            case .installation(let value):
                try await sub(installation: value)
            case .createSomething(let value):
                try await sub(createSomething: value)
            }
        }

        /// @lint.context replayable
        func sub(installation value: Int) async throws {
            try await db.users.update(value)
        }

        /// @lint.context replayable
        func sub(createSomething value: Int) async throws {
            try await db.repoFeed.insert(value)
        }
        """
        var table = EffectSymbolTable()
        let parsed = Parser.parse(source: source)
        table.merge(source: parsed)

        table.applyUpwardInferenceImportAware(
            to: [parsed],
            multiHop: true
        ) { call, _ in
            if let sig = FunctionSignature.from(call: call),
               sig.name == "update" || sig.name == "insert" {
                return .nonIdempotent
            }
            return nil
        }

        let dispatchSig = FunctionSignature(name: "dispatch", argumentLabels: ["event"])
        let dispatchUpward = table.upwardInference(for: dispatchSig)
        #expect(dispatchUpward?.effect == .nonIdempotent)
        #expect((dispatchUpward?.depth ?? 0) >= 2)
    }
}

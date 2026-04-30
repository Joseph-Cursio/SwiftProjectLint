import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Slot 22 — `Task.sleep` under the SwiftConcurrency always-active gate.
/// SwiftConcurrency is a stdlib framework (listed in
/// `alwaysActiveFrameworks`) so the import gate is satisfied by an empty
/// `imports` set. Split off from `FrameworkWhitelistGatingTests` so the
/// base struct stays under SwiftLint's `type_body_length` threshold.
@Suite
struct FrameworkWhitelistSwiftConcurrencyTests {

    // MARK: - Swift Concurrency Task.sleep whitelist (slot 22)

    @Test
    func stdlib_taskSleep_firesWithoutExplicitImport() throws {
        // `Task.sleep(nanoseconds:)` — Swift Concurrency stdlib primitive.
        // Unlike the Vapor / Hummingbird whitelists, SwiftConcurrency is
        // a stdlib framework (listed in `alwaysActiveFrameworks`) so the
        // import gate is satisfied by an empty `imports` set — adopter
        // code never writes `import SwiftConcurrency` because there's
        // no such module. 4-adopter evidence: hummingbird-examples +
        // Uitsmijter + HomeAutomation + Vernissage.
        let call = try firstCall(in: "func f() async throws { try await Task.sleep(nanoseconds: 500_000_000) }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: [], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func stdlib_taskSleep_modernForSpelling_firesAlso() throws {
        // `Task.sleep(for: .seconds(N))` — modern stdlib spelling.
        // The whitelist lookup is name-based, not signature-based, so
        // both `sleep(nanoseconds:)` and `sleep(for:)` resolve to the
        // same `(Task, sleep)` pair.
        let call = try firstCall(in: "func f() async throws { try await Task.sleep(for: .seconds(2)) }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: [], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func stdlib_taskSleep_triedOptional_firesAlso() throws {
        // `try? await Task.sleep(...)` — the exception-swallow spelling
        // used for "best-effort delay" calls. The whitelist classification
        // is on the call site, not the surrounding error handling.
        let call = try firstCall(in: "func f() async { try? await Task.sleep(for: .seconds(60)) }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: [], enabledFrameworks: nil
        ) == .idempotent)
    }

    @Test
    func taskSleep_wrongReceiver_doesNotSilenceBareName() throws {
        // `.sleep()` on a receiver other than `Task`: the slot-22 pair
        // must not fire. The bare name `sleep` is not on any existing
        // idempotent / non-idempotent lexicon, so without the pair the
        // classification falls through to `nil` (unclassified, which
        // is the correct behaviour for an unknown method name).
        let call = try firstCall(in: "func f() async { thread.sleep(forTimeInterval: 1.0) }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: [], enabledFrameworks: nil
        ) == nil)
    }

    @Test
    func configGated_swiftConcurrencyDisabled_taskSleepFallsThrough() throws {
        // Adopter opts out of the `SwiftConcurrency` whitelist via
        // `enabled_framework_whitelists: [...]`. The always-active gate
        // still respects the config opt-out — `isFrameworkActive`
        // short-circuits `importOK` to `true` but returns
        // `enabledOK && importOK` = `false` because enabled excludes
        // SwiftConcurrency. With the slot-22 pair off, `sleep` isn't
        // on any other lexicon, so classification falls through to nil.
        let call = try firstCall(in: "func f() async throws { try await Task.sleep(for: .seconds(1)) }")
        #expect(CallSiteEffectInferrer.infer(
            call: call, imports: [], enabledFrameworks: ["Foundation"]
        ) == nil)
    }

    @Test
    func swiftConcurrency_taskSleep_inferenceReason() throws {
        let call = try firstCall(in: "func f() async throws { try await Task.sleep(for: .seconds(1)) }")
        let reason = CallSiteEffectInferrer.inferenceReason(
            for: call, imports: [], enabledFrameworks: nil
        )
        #expect(reason == "from the SwiftConcurrency primitive `Task.sleep`")
    }

    @Test
    func swiftConcurrency_taskSleep_coexistsWithServerFrameworks() throws {
        // A real adopter file imports Vapor + FluentKit + uses
        // Task.sleep. All three whitelists must coexist without
        // interfering. Also confirms no stdlib-framework false
        // shadowing — a `Task.sleep` call stays idempotent, a
        // `model.save(on:)` stays non-idempotent (Fluent ORM verb).
        let sleepCall = try firstCall(in: "func f() async throws { try await Task.sleep(for: .seconds(1)) }")
        #expect(CallSiteEffectInferrer.infer(
            call: sleepCall, imports: ["Vapor", "FluentKit"], enabledFrameworks: nil
        ) == .idempotent)

        let saveCall = try firstCall(in: "func f() async throws { try await model.save(on: db) }")
        #expect(CallSiteEffectInferrer.infer(
            call: saveCall, imports: ["Vapor", "FluentKit"], enabledFrameworks: nil
        ) == .nonIdempotent)
    }

    @Test
    func alwaysActiveFrameworks_containsSwiftConcurrency() throws {
        // Structural assertion — the always-active set is the data
        // structure that decouples slot 22 from the import gate.
        // Future stdlib additions go here.
        #expect(FrameworkGates.alwaysActiveFrameworks.contains(FrameworkGates.swiftConcurrency))
    }
}

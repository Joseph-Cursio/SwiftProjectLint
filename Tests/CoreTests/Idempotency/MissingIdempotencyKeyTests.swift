import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Phase-2.1 fixtures for the `missingIdempotencyKey` rule — the verifier for
/// the trust the `externally_idempotent` tier grants call sites.
///
/// The rule is deliberately a narrow, high-precision check. It fires on
/// direct call-expression arguments that are known per-invocation generators
/// (`UUID()`, `Date()`, `Date.now`, `arc4random()`) and stays silent on
/// opaque expressions (function parameters, property accesses, local
/// constants). Deeper data-flow analysis belongs to Phase 2 heuristic
/// inference.
@Suite
struct MissingIdempotencyKeyTests {

    private func run(_ source: String) -> MissingIdempotencyKeyVisitor {
        let visitor = MissingIdempotencyKeyVisitor(pattern: MissingIdempotencyKey().pattern)
        visitor.walk(Parser.parse(source: source))
        visitor.analyze()
        return visitor
    }

    // MARK: - Positive: known generators

    @Test
    func uuidCallAsKeyArgument_flags() throws {
        let source = """
        /// @lint.effect externally_idempotent(by: idempotencyKey)
        func charge(idempotencyKey: String, amount: Int) async throws {}

        /// @lint.context replayable
        func handleWebhook(amount: Int) async throws {
            try await charge(idempotencyKey: UUID().uuidString, amount: amount)
        }
        """
        let issues = run(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .missingIdempotencyKey)
        #expect(issue.message.contains("UUID"))
        #expect(issue.message.contains("charge"))
    }

    @Test
    func bareUUIDInit_flags() throws {
        let source = """
        /// @lint.effect externally_idempotent(by: key)
        func send(key: UUID, message: String) async throws {}

        /// @lint.context replayable
        func notify(message: String) async throws {
            try await send(key: UUID(), message: message)
        }
        """
        let issues = run(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("UUID") == true)
    }

    @Test
    func dateNowAsKeyArgument_flags() throws {
        let source = """
        /// @lint.effect externally_idempotent(by: key)
        func charge(key: String, amount: Int) async throws {}

        /// @lint.context replayable
        func handle(amount: Int) async throws {
            try await charge(key: "\\(Date.now)", amount: amount)
        }
        """
        // NOTE: this particular form (string-interpolation around Date.now)
        // is conservatively NOT flagged — the argument expression is a
        // StringLiteralExpr, not a direct MemberAccessExpr. The more direct
        // form below is flagged.
        let issues = run(source).detectedIssues
        #expect(issues.isEmpty)
    }

    @Test
    func dateNowDirectAsKeyArgument_flags() throws {
        let source = """
        /// @lint.effect externally_idempotent(by: key)
        func charge(key: Date, amount: Int) async throws {}

        /// @lint.context replayable
        func handle(amount: Int) async throws {
            try await charge(key: Date.now, amount: amount)
        }
        """
        let issues = run(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Date.now") == true)
    }

    @Test
    func arc4randomAsKeyArgument_flags() throws {
        let source = """
        /// @lint.effect externally_idempotent(by: key)
        func send(key: UInt32, message: String) async throws {}

        /// @lint.context replayable
        func notify(message: String) async throws {
            try await send(key: arc4random(), message: message)
        }
        """
        let issues = run(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("arc4random") == true)
    }

    // MARK: - Negative: opaque expressions (happy path)

    @Test
    func parameterAsKeyArgument_noDiagnostic() {
        // The handler routes its own upstream event-ID parameter into the
        // key argument. The rule has no way to verify eventID itself is
        // stable across retries — that requires data-flow analysis — but
        // it also has no reason to flag it: a function parameter COULD be
        // stable, so conservative silence is correct.
        let source = """
        /// @lint.effect externally_idempotent(by: idempotencyKey)
        func charge(idempotencyKey: String, amount: Int) async throws {}

        /// @lint.context replayable
        func handleWebhook(eventID: String, amount: Int) async throws {
            try await charge(idempotencyKey: eventID, amount: amount)
        }
        """
        #expect(run(source).detectedIssues.isEmpty)
    }

    @Test
    func propertyAccessAsKeyArgument_noDiagnostic() {
        let source = """
        /// @lint.effect externally_idempotent(by: key)
        func charge(key: String, amount: Int) async throws {}

        struct Event { let id: String; let amount: Int }

        /// @lint.context replayable
        func handleWebhook(event: Event) async throws {
            try await charge(key: event.id, amount: event.amount)
        }
        """
        #expect(run(source).detectedIssues.isEmpty)
    }

    @Test
    func localConstantAsKeyArgument_noDiagnostic() {
        // Phase-2.1 limitation: the rule does not follow let-bindings. A
        // local constant holding `UUID()` escapes detection by design —
        // data-flow analysis is out of scope for the narrow check.
        // Documented here so future regressions on this boundary are caught.
        let source = """
        /// @lint.effect externally_idempotent(by: key)
        func charge(key: String, amount: Int) async throws {}

        /// @lint.context replayable
        func handle(amount: Int) async throws {
            let localKey = UUID().uuidString
            try await charge(key: localKey, amount: amount)
        }
        """
        #expect(run(source).detectedIssues.isEmpty)
    }

    // MARK: - Quiet paths: rule has nothing to check

    @Test
    func externallyIdempotentWithoutByQualifier_noDiagnostic_evenOnUUID() {
        // No `(by:)` qualifier means the rule does not know which parameter
        // carries the key. Even an obviously wrong UUID() argument passes
        // silently — not a false negative, but the declared consequence of
        // the annotation being documentary-only.
        let source = """
        /// @lint.effect externally_idempotent
        func charge(idempotencyKey: String, amount: Int) async throws {}

        /// @lint.context replayable
        func handle(amount: Int) async throws {
            try await charge(idempotencyKey: UUID().uuidString, amount: amount)
        }
        """
        #expect(run(source).detectedIssues.isEmpty)
    }

    @Test
    func nonExternallyIdempotentCallee_noDiagnostic() {
        // `idempotencyViolation` / `nonIdempotentInRetryContext` may fire on
        // these; `missingIdempotencyKey` must not — its precondition is an
        // `externally_idempotent` callee.
        let source = """
        /// @lint.effect non_idempotent
        func insert(id: String) async throws {}

        /// @lint.context replayable
        func handle() async throws {
            try await insert(id: UUID().uuidString)
        }
        """
        #expect(run(source).detectedIssues.isEmpty)
    }

    @Test
    func keyLabelAbsentAtCallSite_noDiagnostic() {
        // The callee's `key` parameter has a default. The call site omits
        // it. The rule cannot reach into the callee's declaration to
        // distinguish "defaulted and thus stable" from "omitted and thus
        // fresh-per-call" — both are invisible. Stays silent by design.
        let source = """
        /// @lint.effect externally_idempotent(by: key)
        func charge(key: String = "default", amount: Int) async throws {}

        /// @lint.context replayable
        func handle(amount: Int) async throws {
            try await charge(amount: amount)
        }
        """
        #expect(run(source).detectedIssues.isEmpty)
    }

    @Test
    func escapingClosureBoundary_callInsideTaskNotChecked() {
        // Escaping closure policy mirrors the other idempotency visitors —
        // stops at Task { } and friends. The caller's body walk does not
        // descend past the boundary, so a UUID() key inside Task { } is not
        // flagged by this rule (retry semantics inside Task are their own
        // context question — Phase 1 explicitly defers that).
        let source = """
        /// @lint.effect externally_idempotent(by: key)
        func charge(key: String, amount: Int) async throws {}

        /// @lint.context replayable
        func handle(amount: Int) async throws {
            Task {
                try await charge(key: UUID().uuidString, amount: amount)
            }
        }
        """
        #expect(run(source).detectedIssues.isEmpty)
    }

    // MARK: - Signature resolution

    @Test
    func overloadedCallees_resolveIndependentlyBySignature() throws {
        // Two overloads distinguishable by argument-label signature. Only the
        // one with `(by:)` on its annotation should trigger the rule at its
        // call sites.
        let source = """
        /// @lint.effect externally_idempotent(by: id)
        func charge(id: String, amount: Int) async throws {}

        /// @lint.effect externally_idempotent
        func charge(currency: String, amount: Int) async throws {}

        /// @lint.context replayable
        func handle(amount: Int) async throws {
            try await charge(id: UUID().uuidString, amount: amount)   // flagged
            try await charge(currency: "USD", amount: amount)         // silent — documentary annotation
        }
        """
        let issues = run(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("UUID") == true)
    }
}

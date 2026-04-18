import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Phase-2 fixtures for the `externally_idempotent` lattice tier.
///
/// The tier models functions that are idempotent *only if* routed through a
/// caller-supplied deduplication key — Stripe charges, SES sends, Mailgun
/// deliveries, SNS publishes, any API accepting a client-provided idempotency
/// token. This commit introduces the tier itself and its lattice behaviour.
/// The key-routing check that would verify the token actually reaches the
/// callee is deferred to a follow-up rule (`missingIdempotencyKey`).
///
/// Phase-2 lattice rows relative to `externally_idempotent`:
///
/// | Caller | Callee | Fires? |
/// |---|---|:-:|
/// | idempotent | externally_idempotent | NO (assume key routed) |
/// | observational | externally_idempotent | YES (mutates business state) |
/// | externally_idempotent | idempotent | NO |
/// | externally_idempotent | observational | NO |
/// | externally_idempotent | externally_idempotent | NO (assume key routed) |
/// | externally_idempotent | non_idempotent | YES (breaks keyed guarantee) |
/// | replayable / retry_safe | externally_idempotent | NO (assume key routed) |
@Suite
struct ExternallyIdempotentParserTests {

    @Test
    func parsesExternallyIdempotentEffect() {
        let source = """
        /// @lint.effect externally_idempotent
        func charge(idempotencyKey: String, amount: Int) async throws {}
        """
        let table = EffectSymbolTable.build(from: Parser.parse(source: source))
        let signature = FunctionSignature(
            name: "charge",
            argumentLabels: ["idempotencyKey", "amount"]
        )
        // No `(by:)` qualifier in the source → keyParameter is nil.
        #expect(table.effect(for: signature) == .externallyIdempotent(keyParameter: nil))
    }

    @Test
    func parsesExternallyIdempotentWithByQualifier() {
        // Phase 2.1 grammar: `(by: paramName)` names the parameter that carries
        // the deduplication key. `missingIdempotencyKey` will use this name at
        // call sites; parser round-trip is verified here.
        let source = """
        /// @lint.effect externally_idempotent(by: idempotencyKey)
        func charge(idempotencyKey: String, amount: Int) async throws {}
        """
        let table = EffectSymbolTable.build(from: Parser.parse(source: source))
        let signature = FunctionSignature(
            name: "charge",
            argumentLabels: ["idempotencyKey", "amount"]
        )
        #expect(
            table.effect(for: signature)
                == .externallyIdempotent(keyParameter: "idempotencyKey")
        )
    }

    @Test
    func parsesExternallyIdempotentWithByQualifierWhitespaceVariants() {
        // Parser must tolerate whitespace between the token and the paren,
        // and between the colon and the name. Either form should parse the
        // same keyParameter.
        let tight = """
        /// @lint.effect externally_idempotent(by:key)
        func send(key: String) {}
        """
        let loose = """
        /// @lint.effect externally_idempotent  (by:   key)
        func send(key: String) {}
        """
        let signature = FunctionSignature(name: "send", argumentLabels: ["key"])
        #expect(
            EffectSymbolTable.build(from: Parser.parse(source: tight)).effect(for: signature)
                == .externallyIdempotent(keyParameter: "key")
        )
        #expect(
            EffectSymbolTable.build(from: Parser.parse(source: loose)).effect(for: signature)
                == .externallyIdempotent(keyParameter: "key")
        )
    }

    @Test
    func malformedByQualifier_yieldsNilKeyParameter() {
        // Malformed variants should parse as the tier alone (keyParameter nil)
        // rather than erroring or dropping the annotation entirely. The
        // lattice behaviour still applies; only the key-routing verifier will
        // find nothing to check.
        let noName = """
        /// @lint.effect externally_idempotent(by:)
        func send() {}
        """
        let wrongKey = """
        /// @lint.effect externally_idempotent(on: key)
        func send() {}
        """
        let signature = FunctionSignature(name: "send", argumentLabels: [])
        #expect(
            EffectSymbolTable.build(from: Parser.parse(source: noName)).effect(for: signature)
                == .externallyIdempotent(keyParameter: nil)
        )
        #expect(
            EffectSymbolTable.build(from: Parser.parse(source: wrongKey)).effect(for: signature)
                == .externallyIdempotent(keyParameter: nil)
        )
    }

    @Test
    func camelCaseTokenIsNotAccepted() {
        // Grammar is snake_case throughout (idempotent, non_idempotent,
        // externally_idempotent). A camelCase spelling must be treated as an
        // unrecognised token and ignored silently — same policy as any
        // unknown @lint.effect value.
        let source = """
        /// @lint.effect externallyIdempotent
        func charge() async throws {}
        """
        let table = EffectSymbolTable.build(from: Parser.parse(source: source))
        let signature = FunctionSignature(name: "charge", argumentLabels: [])
        #expect(table.effect(for: signature) == nil)
    }

    @Test
    func parsesAlongsideOtherTiers() {
        let source = """
        /// @lint.effect idempotent
        func upsert() {}

        /// @lint.effect observational
        func log() {}

        /// @lint.effect externally_idempotent
        func charge() {}

        /// @lint.effect non_idempotent
        func insert() {}
        """
        let table = EffectSymbolTable.build(from: Parser.parse(source: source))
        #expect(table.effect(for: FunctionSignature(name: "upsert", argumentLabels: [])) == .idempotent)
        #expect(table.effect(for: FunctionSignature(name: "log", argumentLabels: [])) == .observational)
        #expect(table.effect(for: FunctionSignature(name: "charge", argumentLabels: [])) == .externallyIdempotent(keyParameter: nil))
        #expect(table.effect(for: FunctionSignature(name: "insert", argumentLabels: [])) == .nonIdempotent)
    }
}

@Suite
struct ExternallyIdempotentLatticeTests {

    private func runEffect(_ source: String) -> IdempotencyViolationVisitor {
        let visitor = IdempotencyViolationVisitor(pattern: IdempotencyViolation().pattern)
        visitor.walk(Parser.parse(source: source))
        visitor.analyze()
        return visitor
    }

    private func runContext(_ source: String) -> NonIdempotentInRetryContextVisitor {
        let visitor = NonIdempotentInRetryContextVisitor(
            pattern: NonIdempotentInRetryContext().pattern
        )
        visitor.walk(Parser.parse(source: source))
        visitor.analyze()
        return visitor
    }

    // MARK: - Callee is externally_idempotent (key routing assumed in Phase 2)

    @Test
    func idempotentCallerCallsExternallyIdempotent_noDiagnostic() {
        // The idempotent caller is trusted to route a key through. The
        // missing-key check belongs to a future `missingIdempotencyKey` rule;
        // Phase 2's tier-introduction commit assumes the key is routed so
        // that legitimate usage does not fire.
        let source = """
        /// @lint.effect externally_idempotent
        func charge(idempotencyKey: String, amount: Int) async throws {}

        /// @lint.effect idempotent
        func process(orderID: String, amount: Int) async throws {
            try await charge(idempotencyKey: orderID, amount: amount)
        }
        """
        #expect(runEffect(source).detectedIssues.isEmpty)
    }

    @Test
    func replayableCallerCallsExternallyIdempotent_noDiagnostic() {
        let source = """
        /// @lint.effect externally_idempotent
        func charge(idempotencyKey: String, amount: Int) async throws {}

        /// @lint.context replayable
        func handleWebhook(eventID: String, amount: Int) async throws {
            try await charge(idempotencyKey: eventID, amount: amount)
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    @Test
    func retrySafeCallerCallsExternallyIdempotent_noDiagnostic() {
        let source = """
        /// @lint.effect externally_idempotent
        func charge(idempotencyKey: String, amount: Int) async throws {}

        /// @lint.context retry_safe
        func process(orderID: String, amount: Int) async throws {
            try await charge(idempotencyKey: orderID, amount: amount)
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    @Test
    func observationalCallerCallsExternallyIdempotent_flags() throws {
        // Observational functions must not mutate business state. A keyed
        // external operation is still a business-state mutation — the key
        // only ensures convergence under replay, not that the mutation did
        // not happen. Observational is stricter than both sides of the keyed
        // bargain.
        let source = """
        /// @lint.effect externally_idempotent
        func charge(idempotencyKey: String, amount: Int) async throws {}

        /// @lint.effect observational
        func logOrder(orderID: String, amount: Int) async throws {
            try await charge(idempotencyKey: orderID, amount: amount)
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .idempotencyViolation)
        #expect(issue.message.contains("observational"))
        #expect(issue.message.contains("externally_idempotent"))
        #expect(issue.message.contains("charge"))
    }

    // MARK: - Caller is externally_idempotent

    @Test
    func externallyIdempotentCallsIdempotent_noDiagnostic() {
        let source = """
        /// @lint.effect idempotent
        func upsertOrder(orderID: String) async throws {}

        /// @lint.effect externally_idempotent
        func charge(idempotencyKey: String, amount: Int) async throws {
            try await upsertOrder(orderID: idempotencyKey)
        }
        """
        #expect(runEffect(source).detectedIssues.isEmpty)
    }

    @Test
    func externallyIdempotentCallsObservational_noDiagnostic() {
        let source = """
        /// @lint.effect observational
        func logMetric(_ name: String) {}

        /// @lint.effect externally_idempotent
        func charge(idempotencyKey: String, amount: Int) async throws {
            logMetric("charge.attempt")
        }
        """
        #expect(runEffect(source).detectedIssues.isEmpty)
    }

    @Test
    func externallyIdempotentCallsExternallyIdempotent_noDiagnostic() {
        // Composition holds: a keyed wrapper can delegate to another keyed
        // operation using the same or derived key. The linter assumes the
        // delegation preserves the key; verifying that is the future
        // `missingIdempotencyKey` rule's job.
        let source = """
        /// @lint.effect externally_idempotent
        func stripeCharge(idempotencyKey: String, amount: Int) async throws {}

        /// @lint.effect externally_idempotent
        func billCustomer(idempotencyKey: String, amount: Int) async throws {
            try await stripeCharge(idempotencyKey: idempotencyKey, amount: amount)
        }
        """
        #expect(runEffect(source).detectedIssues.isEmpty)
    }

    @Test
    func externallyIdempotentCallsNonIdempotent_flags() throws {
        // The keyed guarantee is only as strong as its weakest uninstrumented
        // call. Any unconditionally non-idempotent work inside the body
        // re-fires on replay regardless of the caller's idempotency key.
        let source = """
        /// @lint.effect non_idempotent
        func appendToAuditLog(_ event: String) async throws {}

        /// @lint.effect externally_idempotent
        func charge(idempotencyKey: String, amount: Int) async throws {
            try await appendToAuditLog("charge \\(idempotencyKey)")
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .idempotencyViolation)
        #expect(issue.message.contains("externally_idempotent"))
        #expect(issue.message.contains("non_idempotent"))
        #expect(issue.message.contains("appendToAuditLog"))
        // Suggestion guides the user toward the specific Phase-2 remediation
        // paths, not the generic idempotent-alternative suggestion.
        #expect(issue.suggestion?.contains("idempotency key") == true)
    }

    // MARK: - Phase-1 regressions: Phase-2 changes must not disturb existing rows

    @Test
    func phase1Regression_idempotentCallsNonIdempotent_stillFires() {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.effect idempotent
        func process(_ id: Int) async throws {
            try await insert(id)
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
    }

    @Test
    func phase1Regression_replayableCallsNonIdempotent_stillFires() {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.context replayable
        func handler(_ id: Int) async throws {
            try await insert(id)
        }
        """
        let issues = runContext(source).detectedIssues
        #expect(issues.count == 1)
    }
}

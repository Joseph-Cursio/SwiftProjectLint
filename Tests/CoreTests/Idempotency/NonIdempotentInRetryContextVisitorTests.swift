import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct NonIdempotentInRetryContextVisitorTests {

    private func makeVisitor() -> NonIdempotentInRetryContextVisitor {
        let pattern = NonIdempotentInRetryContext().pattern
        return NonIdempotentInRetryContextVisitor(pattern: pattern)
    }

    private func run(source: String) -> NonIdempotentInRetryContextVisitor {
        let visitor = makeVisitor()
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
        visitor.analyze()
        return visitor
    }

    // MARK: - Positive Cases

    @Test
    func replayableCallsNonIdempotent_flags() throws {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ order: Int) async throws {}

        /// @lint.context replayable
        func handle(_ order: Int) async throws {
            try await insert(order)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .nonIdempotentInRetryContext)
        #expect(issue.message.contains("insert"))
        #expect(issue.message.contains("replayable"))
    }

    @Test
    func replayableCallsNonIdempotent_suggestionNamesSwiftIdempotency() throws {
        // Cross-adopter evidence (matool Cognito + tinyfaces Brevo) showed
        // adopters consistently hit the email-on-retry-without-idempotency-key
        // shape and the existing generic "deduplication guard or
        // idempotency-key mechanism" wording didn't point at a concrete fix.
        // The suggestion now names the SwiftIdempotency package surface
        // (IdempotencyKey + @ExternallyIdempotent(by:)) directly so adopters
        // have a discoverable path from diagnostic to remediation.
        let source = """
        /// @lint.effect non_idempotent
        func sendEmail(_ to: String) async throws {}

        /// @lint.context replayable
        func sendMagicEmail(_ to: String) async throws {
            try await sendEmail(to)
        }
        """

        let visitor = run(source: source)

        let issue = try #require(visitor.detectedIssues.first)
        let suggestion = try #require(issue.suggestion)
        #expect(suggestion.contains("IdempotencyKey"))
        #expect(suggestion.contains("@ExternallyIdempotent(by:)"))
        #expect(suggestion.contains("SwiftIdempotency"))
    }

    @Test
    func retrySafeCallsNonIdempotent_flags() throws {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.context retry_safe
        func process(_ id: Int) async throws {
            try await insert(id)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("retry_safe"))
    }

    // MARK: - Negative Cases

    @Test
    func replayableCallsIdempotent_noDiagnostic() {
        let source = """
        /// @lint.effect idempotent
        func upsert(_ id: Int) async throws {}

        /// @lint.context replayable
        func handle(_ id: Int) async throws {
            try await upsert(id)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func unannotatedCaller_noDiagnostic() {
        // Phase 1: only functions with an explicit @context annotation are
        // subject to the rule. Unannotated callers stay silent.
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        func handle(_ id: Int) async throws {
            try await insert(id)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func nonIdempotentInsideEscapingTaskClosure_notFlagged() {
        // Closure-traversal policy: escaping closures (Task { }, withTaskGroup,
        // .task { }) are intentionally out of Phase 1 scope. A @context replayable
        // function that spawns a Task containing a non-idempotent call produces
        // no diagnostic — this is a known limitation documented on the visitor.
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.context replayable
        func handle(_ id: Int) async throws {
            Task {
                try await insert(id)
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

}

/// Cross-rule fixture: a function annotated with both an effect and a context.
/// Exercises the expectation that both rules are independent and both fire
/// when their respective conditions are met.
@Suite
struct IdempotencyRuleInteractionTests {

    @Test
    func bothRulesFireIndependently() throws {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.effect idempotent
        /// @lint.context replayable
        func handle(_ id: Int) async throws {
            try await insert(id)
        }
        """

        let sourceFile = Parser.parse(source: source)

        let violationVisitor = IdempotencyViolationVisitor(
            pattern: IdempotencyViolation().pattern
        )
        violationVisitor.walk(sourceFile)
        violationVisitor.analyze()

        let contextVisitor = NonIdempotentInRetryContextVisitor(
            pattern: NonIdempotentInRetryContext().pattern
        )
        contextVisitor.walk(sourceFile)
        contextVisitor.analyze()

        #expect(violationVisitor.detectedIssues.count == 1)
        #expect(violationVisitor.detectedIssues.first?.ruleName == .idempotencyViolation)
        #expect(contextVisitor.detectedIssues.count == 1)
        #expect(contextVisitor.detectedIssues.first?.ruleName == .nonIdempotentInRetryContext)
    }
}

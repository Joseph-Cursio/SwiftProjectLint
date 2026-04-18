import Testing
@testable import Core
@testable import SwiftProjectLintRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Phase-2 third-slice: closure-binding annotation end-to-end rule tests.
/// Verifies that `/// @lint.context` / `/// @lint.effect` on a variable
/// decl initialised by a closure literal produces the same diagnostic
/// shape as the equivalent annotation on a function declaration.
@Suite
struct ClosureBindingRuleTests {

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

    // MARK: - Retry-context rule on closure-bound handlers

    @Test
    func replayableClosureBinding_callsPrefixSend_flags() throws {
        // Canonical R6 closure-handler shape: annotated binding calls a
        // `send*`-prefixed function in its body.
        let source = """
        func sendEmail(_ msg: String) {}

        /// @lint.context replayable
        let handler: @Sendable (String) -> Void = { msg in
            sendEmail(msg)
        }
        """
        let issues = runContext(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .nonIdempotentInRetryContext)
        #expect(issue.message.contains("handler"))
        #expect(issue.message.contains("replayable"))
        #expect(issue.message.contains("sendEmail"))
    }

    @Test
    func replayableClosureBinding_benignBody_noDiagnostic() {
        let source = """
        /// @lint.context replayable
        let handler: @Sendable (Int) -> Int = { x in
            return x + 1
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    @Test
    func replayableVarBinding_callsExactWhitelistName_flags() {
        let source = """
        func publish(_ event: String) {}

        /// @lint.context replayable
        var handler: @Sendable (String) -> Void = { e in
            publish(e)
        }
        """
        let issues = runContext(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("publish") == true)
    }

    // MARK: - Effect rule on closure-bound handlers

    @Test
    func observationalClosureBinding_callsPrefixEnqueue_flags() throws {
        // Observational → inferred non_idempotent (prefix `enqueue`+`B`)
        // is a classic contract violation for the effect rule.
        let source = """
        struct Queue { func enqueueBatch(_ items: [String]) {} }

        /// @lint.effect observational
        let audit: @Sendable (Queue, [String]) -> Void = { q, items in
            q.enqueueBatch(items)
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.ruleName == .idempotencyViolation)
        #expect(issue.message.contains("audit"))
        #expect(issue.message.contains("observational"))
        #expect(issue.message.contains("enqueueBatch"))
    }

    @Test
    func idempotentClosureBinding_callsExactNonIdempotentName_flags() {
        let source = """
        func insert(_ row: Int) {}

        /// @lint.effect idempotent
        let writer: @Sendable (Int) -> Void = { row in
            insert(row)
        }
        """
        let issues = runEffect(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("writer") == true)
    }

    // MARK: - Scope boundary — nested closure-bound bindings are independent

    @Test
    func unannotatedNestedClosureBinding_inheritsOuterContext() {
        // Unannotated closure bindings behave like any other non-escape
        // closure expression: they're walked inline as part of the outer
        // context. This preserves the existing escape-closure policy
        // (e.g. `let work = { insert(id) }; await work()` flags even
        // without an annotation on `work`).
        let source = """
        func publish(_ event: String) {}

        /// @lint.context replayable
        func outer() {
            let inner: @Sendable (String) -> Void = { e in
                publish(e)
            }
            _ = inner
        }
        """
        let issues = runContext(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("outer") == true)
    }

    @Test
    func annotatedNestedClosureBinding_firesOnItsOwnContext() {
        // When the inner closure binding carries its own annotation, it
        // becomes an independent analysis site. The outer function's
        // analyzeBody skips descending — diagnostic credits the inner
        // binding, not the outer function. This is the asymmetry with
        // unannotated bindings.
        let source = """
        func publish(_ event: String) {}

        func outer() {
            /// @lint.context replayable
            let inner: @Sendable (String) -> Void = { e in
                publish(e)
            }
            _ = inner
        }
        """
        let issues = runContext(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("inner") == true)
    }

    @Test
    func annotatedInnerBindingSuppressesOuterSiteDoubleFire() {
        // Regression guard: both `outer` and `inner` are annotated
        // replayable. The closure body's `publish(e)` should fire EXACTLY
        // ONCE — credited to `inner`, not double-credited to both.
        let source = """
        func publish(_ event: String) {}

        /// @lint.context replayable
        func outer() {
            /// @lint.context replayable
            let inner: @Sendable (String) -> Void = { e in
                publish(e)
            }
            _ = inner
        }
        """
        let issues = runContext(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("inner") == true)
    }

    // MARK: - Stored-property closures on type declarations

    @Test
    func storedPropertyClosureOnClass_flags() {
        let source = """
        func sendEmail(_ msg: String) {}

        class Mailer {
            /// @lint.context replayable
            let handler: @Sendable (String) -> Void = { msg in
                sendEmail(msg)
            }
        }
        """
        let issues = runContext(source).detectedIssues
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("handler") == true)
    }

    @Test
    func storedPropertyClosureOnActor_flags() {
        let source = """
        func sendEmail(_ msg: String) {}

        actor MailerActor {
            /// @lint.context replayable
            let handler: @Sendable (String) -> Void = { msg in
                sendEmail(msg)
            }
        }
        """
        #expect(runContext(source).detectedIssues.count == 1)
    }

    // MARK: - Non-annotated / non-closure bindings are no-ops

    @Test
    func unannotatedClosureBinding_noDiagnostic() {
        let source = """
        func sendEmail(_ msg: String) {}

        let handler: @Sendable (String) -> Void = { msg in
            sendEmail(msg)
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    @Test
    func annotatedNonClosureBinding_noDiagnostic() {
        // Annotation on a non-closure `let` is semantically meaningless.
        // Parser sees it; rule visitor skips because closureInitializer is nil.
        let source = """
        /// @lint.context replayable
        let count: Int = 42
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    @Test
    func multiBindingDecl_notAnnotatable() {
        // The closureInitializer helper returns nil for multi-binding decls,
        // so the rule has no anchor point. No diagnostic regardless of the
        // bodies' content.
        let source = """
        func publish(_ event: String) {}

        /// @lint.context replayable
        let a: () -> Void = { publish("a") }, b: () -> Void = { publish("b") }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }

    // MARK: - Escaping-closure boundary still applies inside the body

    @Test
    func escapingClosureInsideAnnotatedBinding_doesNotFire() {
        // Non-idempotent call inside a `Task { }` escaping boundary
        // inside the annotated closure's body stays silent (existing
        // escape-closure policy).
        let source = """
        func publish(_ event: String) {}

        /// @lint.context replayable
        let handler: @Sendable (String) -> Void = { e in
            Task {
                publish(e)
            }
        }
        """
        #expect(runContext(source).detectedIssues.isEmpty)
    }
}

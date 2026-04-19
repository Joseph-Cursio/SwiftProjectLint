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

    // MARK: - Trailing-closure annotation (round-11 grammar extension)
    //
    // Closure-based handlers (the Vapor / Hummingbird / Lambda idiom
    // `app.on(...) { req in ... }`) become annotatable: a doc comment
    // on the enclosing call statement attaches to the trailing closure.

    @Test
    func trailingClosureAnnotatedReplayable_firesOnNonIdempotent() throws {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        func routes(_ app: App) throws {
            /// @lint.context replayable
            app.post("orders") { req in
                try await insert(req.id)
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("insert"))
        #expect(issue.message.contains("replayable"))
        #expect(issue.message.contains("closure"))
    }

    @Test
    func trailingClosureAnnotatedRetrySafe_firesOnNonIdempotent() throws {
        let source = """
        /// @lint.effect non_idempotent
        func publishEvent(_ payload: String) async throws {}

        func configure(_ app: App) throws {
            /// @lint.context retry_safe
            app.scheduled("nightly") { ctx in
                try await publishEvent("tick")
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.message.contains("retry_safe") == true)
    }

    @Test
    func trailingClosureUnannotated_staysSilent() {
        // No `@lint.context` above the call → the closure isn't an
        // analysis site, and its non-idempotent callee produces no
        // diagnostic. Preserves the round-6 precision profile.
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        func routes(_ app: App) throws {
            app.post("orders") { req in
                try await insert(req.id)
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func trailingClosureAnnotationOnCallWithoutClosure_staysSilent() {
        // Doc comment above a call that has NO trailing closure — the
        // annotation has no closure to attach to. Silent; no crash, no
        // diagnostic.
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        func routes(_ app: App) throws {
            /// @lint.context replayable
            app.configure()
            try await insert(1)
        }
        """

        let visitor = run(source: source)

        // `insert(1)` is outside any annotated site, so no diagnostic.
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func trailingClosureWithAnnotatedCalleeInside_firesOnceNotTwice() throws {
        // Regression: the annotated trailing closure is its own site.
        // If the OUTER enclosing function is ALSO annotated, we must not
        // double-count the inner non-idempotent call.
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.context replayable
        func routes(_ app: App) throws {
            /// @lint.context replayable
            app.post("orders") { req in
                try await insert(req.id)
            }
        }
        """

        let visitor = run(source: source)

        // Expected: the inner `insert` call fires exactly once, from
        // the inner analysis site (the trailing closure), not from both
        // the outer function site AND the inner closure.
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func trailingClosureIdempotentCallee_staysSilent() {
        // Confirms the positive path: an idempotent callee in an annotated
        // trailing closure produces no diagnostic.
        let source = """
        /// @lint.effect idempotent
        func upsert(_ id: Int) async throws {}

        func routes(_ app: App) throws {
            /// @lint.context replayable
            app.post("orders") { req in
                try await upsert(req.id)
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Prefix-statement annotation (return-trailing-annotation slice)
    //
    // Surfaced on the TCA adopter round
    // (`swiftIdempotency/docs/swift-composable-architecture/trial-findings.md`).
    // Doc comments above `return <call>`, `try <call>`, `await <call>`,
    // `let x = <call>`, and ternary branches bind to the keyword token
    // rather than the call's first token. The visitor now walks the
    // enclosing `CodeBlockItemSyntax` to recover the annotation in these
    // shapes.

    @Test
    func trailingClosureAnnotatedReplayable_underReturnCall_fires() throws {
        // The TCA canonical shape: `return .run { send in ... }`.
        let source = """
        enum Effect {
            static func run<A>(_ body: (Int) async throws -> Void) -> Effect<A> { fatalError() }
        }

        /// @lint.effect non_idempotent
        func sendNotification(_ id: Int) async throws {}

        func reduce(_ id: Int) -> Effect<Int> {
            /// @lint.context replayable
            return Effect.run { send in
                try await sendNotification(id)
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.message.contains("sendNotification") == true)
    }

    @Test
    func trailingClosureAnnotatedReplayable_underTryPrefix_fires() throws {
        let source = """
        /// @lint.effect non_idempotent
        func sendNotification(_ id: Int) async throws {}

        func wrapper(_ id: Int) throws {
            /// @lint.context replayable
            try withThrowingCallback { send in
                try await sendNotification(id)
            }
        }

        func withThrowingCallback(_ body: ((Int) async throws -> Void) throws -> Void) throws {}
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func trailingClosureAnnotatedReplayable_underAwaitPrefix_fires() throws {
        let source = """
        /// @lint.effect non_idempotent
        func sendNotification(_ id: Int) async throws {}

        func wrapper(_ id: Int) async throws {
            /// @lint.context replayable
            await withAsyncCallback { send in
                try await sendNotification(id)
            }
        }

        func withAsyncCallback(_ body: ((Int) async throws -> Void) async -> Void) async {}
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func trailingClosureAnnotatedReplayable_underLetAssignment_fires() throws {
        let source = """
        /// @lint.effect non_idempotent
        func sendNotification(_ id: Int) async throws {}

        func builder(_ id: Int) {
            /// @lint.context replayable
            let effect = EffectBuilder.build { send in
                try await sendNotification(id)
            }
            _ = effect
        }

        enum EffectBuilder {
            static func build(_ body: (Int) async throws -> Void) -> Int { 0 }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func trailingClosureAnnotatedReplayable_underTernaryBranch_fires() throws {
        // TCA EffectsBasics shape: annotation between `?` and `:` branches.
        let source = """
        /// @lint.effect non_idempotent
        func sendNotification(_ id: Int) async throws {}

        enum Effect<A> {
            static var none: Effect<A> { fatalError() }
            static func run(_ body: (Int) async throws -> Void) -> Effect<A> { fatalError() }
        }

        func reduce(_ condition: Bool, _ id: Int) -> Effect<Int> {
            return condition
                ? .none
                /// @lint.context replayable
                : Effect.run { send in
                    try await sendNotification(id)
                }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func annotationInEarlierStatement_doesNotLeakIntoLaterCall() {
        // The CodeBlockItem boundary isolates annotations. An annotation on
        // one statement must not silently attach to the following
        // statement's trailing-closure call.
        let source = """
        /// @lint.effect non_idempotent
        func sendNotification(_ id: Int) async throws {}

        func handler(_ id: Int) throws {
            /// @lint.context replayable
            let marker = 1

            withCallback { send in
                try await sendNotification(id)
            }
        }

        func withCallback(_ body: ((Int) async throws -> Void) -> Void) {}
        """

        let visitor = run(source: source)

        // The `let marker = 1` consumes the annotation (it has no closure,
        // so it never becomes an analysis site — but its CodeBlockItem owns
        // the trivia). The subsequent `withCallback { ... }` is its own
        // CodeBlockItem with no annotation. No diagnostic.
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func returnCallShape_strictReplayableAlsoCarried() throws {
        // The same prefix-statement shape must carry through for
        // strict_replayable as the label on the emitted message.
        let source = """
        enum Effect<A> {
            static func run(_ body: (Int) async throws -> Void) -> Effect<A> { fatalError() }
        }

        /// @lint.effect non_idempotent
        func sendNotification(_ id: Int) async throws {}

        func reduce(_ id: Int) -> Effect<Int> {
            /// @lint.context strict_replayable
            return Effect.run { send in
                try await sendNotification(id)
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        #expect(
            visitor.detectedIssues.first?.message.contains("strict_replayable") == true
        )
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

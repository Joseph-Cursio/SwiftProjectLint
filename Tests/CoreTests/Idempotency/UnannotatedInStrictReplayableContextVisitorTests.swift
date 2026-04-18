import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

/// Unit tests for the `unannotatedInStrictReplayableContext` rule —
/// round-9 strict-replayable slice. See
/// `docs/claude_phase_2_strict_replayable_plan.md`.
@Suite
struct UnannotatedInStrictReplayableContextVisitorTests {

    private func makeVisitor() -> UnannotatedInStrictReplayableContextVisitor {
        let pattern = UnannotatedInStrictReplayableContext().pattern
        return UnannotatedInStrictReplayableContextVisitor(pattern: pattern)
    }

    private func run(source: String) -> UnannotatedInStrictReplayableContextVisitor {
        let visitor = makeVisitor()
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
        visitor.analyze()
        return visitor
    }

    /// File-cache variant for tests that depend on upward inference. The
    /// symbol table's `applyUpwardInference` only traverses files passed
    /// via the cache; the bare-visitor `init(pattern:)` path leaves the
    /// cache empty and upward inference is a no-op.
    private func runWithCache(
        _ files: [String: String]
    ) -> UnannotatedInStrictReplayableContextVisitor {
        let cache: [String: SourceFileSyntax] = files.mapValues { Parser.parse(source: $0) }
        let visitor = UnannotatedInStrictReplayableContextVisitor(fileCache: cache)
        visitor.setPattern(UnannotatedInStrictReplayableContext().pattern)
        for (path, source) in cache {
            visitor.setFilePath(path)
            visitor.setSourceLocationConverter(
                SourceLocationConverter(fileName: path, tree: source)
            )
            visitor.walk(source)
        }
        visitor.finalizeAnalysis()
        return visitor
    }

    // MARK: - Core positive cases — rule fires on unclassified callees

    @Test
    func strictReplayable_unannotatedCallee_flags() throws {
        let source = """
        func mystery(_ id: Int) async throws {}

        /// @lint.context strict_replayable
        func handle(_ id: Int) async throws {
            try await mystery(id)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .unannotatedInStrictReplayableContext)
        #expect(issue.message.contains("mystery"))
        #expect(issue.message.contains("strict_replayable"))
    }

    @Test
    func strictReplayable_multipleUnannotatedCallees_eachFlagged() throws {
        let source = """
        func alpha() {}
        func beta() {}
        func gamma() {}

        /// @lint.context strict_replayable
        func handle() async throws {
            alpha()
            beta()
            gamma()
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 3)
    }

    // MARK: - Core negative cases — proven classifications pass silently

    @Test
    func strictReplayable_declaredIdempotentCallee_silent() {
        let source = """
        /// @lint.effect idempotent
        func upsert(_ id: Int) async throws {}

        /// @lint.context strict_replayable
        func handle(_ id: Int) async throws {
            try await upsert(id)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func strictReplayable_declaredObservationalCallee_silent() {
        let source = """
        /// @lint.effect observational
        func audit(_ message: String) {}

        /// @lint.context strict_replayable
        func handle() async throws {
            audit("hello")
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func strictReplayable_externallyIdempotentCallee_silent() {
        let source = """
        /// @lint.effect externally_idempotent(by: "key")
        func sendEmail(idempotencyKey: String) async throws {}

        /// @lint.context strict_replayable
        func handle() async throws {
            try await sendEmail(idempotencyKey: "evt_1")
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func strictReplayable_declaredNonIdempotentCallee_silent_existingRuleHandles() {
        // A declared non_idempotent callee is classified — the EXISTING
        // `nonIdempotentInRetryContext` rule fires. This visitor must
        // defer to avoid double-firing.
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.context strict_replayable
        func handle(_ id: Int) async throws {
            try await insert(id)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Heuristic classification defers

    @Test
    func strictReplayable_heuristicNonIdempotentCallee_silent() {
        // `sendNotification` matches the prefix heuristic → nonIdempotent.
        // Existing rule handles; this visitor defers.
        let source = """
        func sendNotification(to: String) async throws {}

        /// @lint.context strict_replayable
        func handle() async throws {
            try await sendNotification(to: "alice")
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func strictReplayable_heuristicObservationalCallee_silent() {
        // A logger-shaped receiver plus a log-level method matches the
        // observational heuristic. `logger` comes in as a parameter so
        // the test doesn't first trip over the `Logger(label:)`
        // constructor call (which would itself be unclassified).
        struct LoggerStub { func info(_ message: String) {} }
        _ = LoggerStub.self  // suppress unused-type warning in release builds

        let source = """
        struct LoggerStub { func info(_ message: String) {} }

        /// @lint.context strict_replayable
        func handle(logger: LoggerStub) async throws {
            logger.info("event received")
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Upward inference defers

    @Test
    func strictReplayable_upwardInferredCallee_silent() {
        // `wrapper` is unannotated but its body only calls idempotent
        // primitives. Multi-hop upward inference classifies it.
        // Upward inference needs the fileCache pathway.
        let visitor = runWithCache([
            "Chain.swift": """
            /// @lint.effect idempotent
            func leaf(_ id: Int) async throws {}

            func wrapper(_ id: Int) async throws {
                try await leaf(id)
            }

            /// @lint.context strict_replayable
            func handle(_ id: Int) async throws {
                try await wrapper(id)
            }
            """
        ])

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Collision-withdrawn silences

    @Test
    func strictReplayable_collidingAnnotationsOnCallee_silent() {
        // Callee has two conflicting effect annotations → collision,
        // neither inference runs. Visitor must not double-fire.
        let source = """
        /// @lint.effect idempotent
        /// @lint.effect non_idempotent
        func conflicted() async throws {}

        /// @lint.context strict_replayable
        func handle() async throws {
            try await conflicted()
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Context scope

    @Test
    func replayableCaller_unannotatedCallee_silent() {
        // Regular `replayable` must keep its round-6 precision profile.
        // The new rule only fires on strict_replayable sites.
        let source = """
        func mystery(_ id: Int) async throws {}

        /// @lint.context replayable
        func handle(_ id: Int) async throws {
            try await mystery(id)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func retrySafeCaller_unannotatedCallee_silent() {
        let source = """
        func mystery(_ id: Int) async throws {}

        /// @lint.context retry_safe
        func handle(_ id: Int) async throws {
            try await mystery(id)
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func onceCaller_unannotatedCallee_silent() {
        // @context once is an inverse contract; strict_replayable's rule
        // doesn't apply.
        let source = """
        func migrate() async throws {}

        /// @lint.context once
        func handle() async throws {
            try await migrate()
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func unannotatedCaller_anything_silent() {
        // No context annotation → rule not engaged at all.
        let source = """
        func mystery() async throws {}

        func handle() async throws {
            try await mystery()
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Escape hatches

    @Test
    func strictReplayable_insideEscapingTaskClosure_silent() {
        // Same escaping-closure policy as existing retry-context rule.
        let source = """
        func mystery() async throws {}

        /// @lint.context strict_replayable
        func handle() async throws {
            Task {
                try await mystery()
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Closure-bound strict_replayable sites

    @Test
    func strictReplayable_onClosureBinding_flagsUnannotated() throws {
        let source = """
        func mystery() async throws {}

        /// @lint.context strict_replayable
        let handler: @Sendable () async throws -> Void = {
            try await mystery()
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("handler"))
        #expect(issue.message.contains("mystery"))
    }

    // MARK: - Nested context-annotated declarations don't leak

    @Test
    func strictReplayable_nestedReplayableBinding_doesNotFireOnInnerCallees() {
        // Nested `@lint.context replayable` closure binding is its own
        // analysis site under the existing rule — the outer strict
        // rule must not descend into it.
        let source = """
        func outer() async throws {}
        func inner() async throws {}

        /// @lint.context strict_replayable
        func handle() async throws {
            try await outer()
            /// @lint.context replayable
            let nested: @Sendable () async throws -> Void = {
                try await inner()
            }
            _ = nested
        }
        """

        let visitor = run(source: source)

        // Only `outer` fires (direct strict callee). `inner` is inside
        // the nested replayable binding and is silent.
        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.message.contains("outer") == true)
    }
}

/// Cross-rule interaction: strict_replayable + declared non-idempotent callee
/// should fire ONLY the existing rule (never double-fire).
@Suite
struct StrictReplayableRuleInteractionTests {

    @Test
    func strictCallsDeclaredNonIdempotent_onlyExistingRuleFires() throws {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.context strict_replayable
        func handle(_ id: Int) async throws {
            try await insert(id)
        }
        """

        let sourceFile = Parser.parse(source: source)

        let existingVisitor = NonIdempotentInRetryContextVisitor(
            pattern: NonIdempotentInRetryContext().pattern
        )
        existingVisitor.walk(sourceFile)
        existingVisitor.analyze()

        let newVisitor = UnannotatedInStrictReplayableContextVisitor(
            pattern: UnannotatedInStrictReplayableContext().pattern
        )
        newVisitor.walk(sourceFile)
        newVisitor.analyze()

        #expect(existingVisitor.detectedIssues.count == 1)
        #expect(existingVisitor.detectedIssues.first?.ruleName == .nonIdempotentInRetryContext)
        #expect(existingVisitor.detectedIssues.first?.message.contains("strict_replayable") == true)
        #expect(newVisitor.detectedIssues.isEmpty)
    }

    @Test
    func strictCallsUnannotated_onlyNewRuleFires() throws {
        let source = """
        func mystery() async throws {}

        /// @lint.context strict_replayable
        func handle() async throws {
            try await mystery()
        }
        """

        let sourceFile = Parser.parse(source: source)

        let existingVisitor = NonIdempotentInRetryContextVisitor(
            pattern: NonIdempotentInRetryContext().pattern
        )
        existingVisitor.walk(sourceFile)
        existingVisitor.analyze()

        let newVisitor = UnannotatedInStrictReplayableContextVisitor(
            pattern: UnannotatedInStrictReplayableContext().pattern
        )
        newVisitor.walk(sourceFile)
        newVisitor.analyze()

        #expect(existingVisitor.detectedIssues.isEmpty)
        #expect(newVisitor.detectedIssues.count == 1)
        #expect(newVisitor.detectedIssues.first?.ruleName == .unannotatedInStrictReplayableContext)
    }
}

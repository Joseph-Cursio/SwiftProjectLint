import SwiftEffectInference
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Unit tests for the `unannotatedInStrictReplayableContext` rule —
/// round-9 strict-replayable slice. See
/// `docs/claude_phase_2_strict_replayable_plan.md`.
@Suite
struct UnannotatedStrictReplayableVisitorTests {

    private func makeVisitor() -> UnannotatedStrictReplayableVisitor {
        let pattern = UnannotatedInStrictReplayableContext().pattern
        return UnannotatedStrictReplayableVisitor(pattern: pattern)
    }

    func run(source: String) -> UnannotatedStrictReplayableVisitor {
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
    ) -> UnannotatedStrictReplayableVisitor {
        let cache: [String: SourceFileSyntax] = files.mapValues { Parser.parse(source: $0) }
        let visitor = UnannotatedStrictReplayableVisitor(fileCache: cache)
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
    func strictReplayable_multipleUnannotatedCallees_eachFlagged() {
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
        struct LoggerStub { func info(_ _: String) { /* no-op */ } }
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
            """,
        ])

        #expect(visitor.detectedIssues.isEmpty)
    }
}

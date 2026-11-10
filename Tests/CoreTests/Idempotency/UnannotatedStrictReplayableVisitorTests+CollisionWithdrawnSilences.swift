import SwiftEffectInference
import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

extension UnannotatedStrictReplayableVisitorTests {
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
}

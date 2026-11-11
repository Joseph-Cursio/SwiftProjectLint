import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Annotation-grammar tests for `NonIdempotentInRetryContext`: the
/// trailing-closure (round-11) and prefix-statement (return-trailing)
/// extensions that attach `@lint.context` to closure-based sites.
@Suite
struct NonIdempotentInRetryAnnotationTests {

    private func makeVisitor() -> NonIdempotentInRetryContextVisitor {
        let pattern = NonIdempotentInRetryContext().pattern
        return NonIdempotentInRetryContextVisitor(pattern: pattern)
    }

    func run(source: String) -> NonIdempotentInRetryContextVisitor {
        let visitor = makeVisitor()
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
        visitor.analyze()
        return visitor
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
    func trailingClosureAnnotatedRetrySafe_firesOnNonIdempotent() {
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
    func trailingClosureWithAnnotatedCalleeInside_firesOnceNotTwice() {
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
}

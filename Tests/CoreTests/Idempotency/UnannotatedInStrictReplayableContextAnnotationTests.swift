import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Annotation-grammar tests for `UnannotatedInStrictReplayableContext`:
/// the trailing-closure (round-11) and prefix-statement (return-trailing)
/// extensions that attach `@lint.context strict_replayable` to
/// closure-based sites.
@Suite
struct UnannotatedInStrictReplayableContextAnnotationTests {

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

    // MARK: - Trailing-closure annotation (round-11 grammar extension)

    @Test
    func strictReplayable_onTrailingClosure_flagsUnannotated() throws {
        let source = """
        func mystery() {}

        func routes(_ app: App) throws {
            /// @lint.context strict_replayable
            app.post("x") { req in
                mystery()
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("closure"))
        #expect(issue.message.contains("mystery"))
        #expect(issue.message.contains("strict_replayable"))
    }

    @Test
    func strictReplayable_onTrailingClosure_silentOnIdempotentCallee() {
        let source = """
        /// @lint.effect idempotent
        func upsert(_ id: Int) {}

        func routes(_ app: App) throws {
            /// @lint.context strict_replayable
            app.post("x") { req in
                upsert(1)
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func replayableOnTrailingClosure_doesNotFireStrictRule() {
        // `@lint.context replayable` on a closure — existing retry-context
        // rule applies, but the new strict rule stays silent.
        let source = """
        func mystery() {}

        func routes(_ app: App) throws {
            /// @lint.context replayable
            app.post("x") { req in
                mystery()
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

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

    // MARK: - Prefix-statement annotation (return-trailing-annotation slice)
    //
    // Same shape as the matching tests in
    // `NonIdempotentInRetryContextVisitorTests`; strict mode needs the
    // same trivia lookup to create analysis sites for
    // `return .run { ... }` / ternary-branch trailing-closure calls.

    @Test
    func strictReplayable_underReturnCall_firesOnUnannotated() throws {
        let source = """
        enum Effect<A> {
            static func run(_ body: (Int) async throws -> Void) -> Effect<A> { fatalError() }
        }

        func mystery(_ id: Int) async throws {}

        func reduce(_ id: Int) -> Effect<Int> {
            /// @lint.context strict_replayable
            return Effect.run { send in
                try await mystery(id)
            }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.message.contains("mystery") == true)
    }

    @Test
    func strictReplayable_underTernaryBranch_firesOnUnannotated() throws {
        let source = """
        enum Effect<A> {
            static var none: Effect<A> { fatalError() }
            static func run(_ body: (Int) async throws -> Void) -> Effect<A> { fatalError() }
        }

        func mystery(_ id: Int) async throws {}

        func reduce(_ condition: Bool, _ id: Int) -> Effect<Int> {
            return condition
                ? .none
                /// @lint.context strict_replayable
                : Effect.run { send in
                    try await mystery(id)
                }
        }
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func strictReplayable_unrelatedEarlierAnnotation_doesNotLeak() {
        // Regression guard: an earlier statement's annotation must not
        // attach to a later trailing-closure call in the same scope.
        let source = """
        func mystery(_ id: Int) async throws {}

        func handler(_ id: Int) throws {
            /// @lint.context strict_replayable
            let marker = 1

            withCallback { send in
                try await mystery(id)
            }
        }

        func withCallback(_ body: ((Int) async throws -> Void) -> Void) {}
        """

        let visitor = run(source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

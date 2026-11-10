import SwiftProjectLintModels
@testable import SwiftProjectLintVisitors
import Testing

extension NonIdempotentInRetryAnnotationTests {
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
    func trailingClosureAnnotatedReplayable_underReturnCall_fires() {
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
    func trailingClosureAnnotatedReplayable_underTryPrefix_fires() {
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
    func trailingClosureAnnotatedReplayable_underAwaitPrefix_fires() {
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
    func trailingClosureAnnotatedReplayable_underLetAssignment_fires() {
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
    func trailingClosureAnnotatedReplayable_underTernaryBranch_fires() {
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
    func returnCallShape_strictReplayableAlsoCarried() {
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

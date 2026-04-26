import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Locks in the Phase-1 closure-traversal policy: the body check stops at
/// trailing closures of structured-concurrency / SwiftUI escape boundaries.
/// One fixture per whitelisted callee to guard against regression if the
/// whitelist drifts or the `isEscapingClosure` walker is refactored.
///
/// Each fixture uses the same declared pair:
///   - `@lint.effect non_idempotent` callee
///   - annotated caller whose body spawns the escape boundary and calls the
///     non_idempotent callee inside the trailing closure
///
/// Expected: zero diagnostics. If a variant regresses and the visitor descends
/// into the trailing closure, the fixture will fail.
@Suite
struct IdempotencyEscapingClosureTests {

    private func runEffect(source: String) -> IdempotencyViolationVisitor {
        let visitor = IdempotencyViolationVisitor(pattern: IdempotencyViolation().pattern)
        visitor.walk(Parser.parse(source: source))
        visitor.analyze()
        return visitor
    }

    private func runContext(source: String) -> NonIdempotentInRetryContextVisitor {
        let visitor = NonIdempotentInRetryContextVisitor(
            pattern: NonIdempotentInRetryContext().pattern
        )
        visitor.walk(Parser.parse(source: source))
        visitor.analyze()
        return visitor
    }

    // MARK: - @effect idempotent caller + escape boundary

    @Test
    func taskBraceIsEscaping_idempotentCaller() {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.effect idempotent
        func process(_ id: Int) async throws {
            Task {
                try await insert(id)
            }
        }
        """
        #expect(runEffect(source: source).detectedIssues.isEmpty)
    }

    @Test
    func taskDetachedIsEscaping_idempotentCaller() {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.effect idempotent
        func process(_ id: Int) async throws {
            Task.detached {
                try await insert(id)
            }
        }
        """
        #expect(runEffect(source: source).detectedIssues.isEmpty)
    }

    @Test
    func withTaskGroupIsEscaping_idempotentCaller() {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.effect idempotent
        func process(_ ids: [Int]) async throws {
            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask {
                        try? await insert(id)
                    }
                }
            }
        }
        """
        #expect(runEffect(source: source).detectedIssues.isEmpty)
    }

    @Test
    func withThrowingTaskGroupIsEscaping_idempotentCaller() {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.effect idempotent
        func process(_ ids: [Int]) async throws {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for id in ids {
                    group.addTask {
                        try await insert(id)
                    }
                }
            }
        }
        """
        #expect(runEffect(source: source).detectedIssues.isEmpty)
    }

    @Test
    func withDiscardingTaskGroupIsEscaping_idempotentCaller() {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.effect idempotent
        func process(_ ids: [Int]) async throws {
            await withDiscardingTaskGroup { group in
                for id in ids {
                    group.addTask {
                        try? await insert(id)
                    }
                }
            }
        }
        """
        #expect(runEffect(source: source).detectedIssues.isEmpty)
    }

    @Test
    func withThrowingDiscardingTaskGroupIsEscaping_idempotentCaller() {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.effect idempotent
        func process(_ ids: [Int]) async throws {
            try await withThrowingDiscardingTaskGroup { group in
                for id in ids {
                    group.addTask {
                        try await insert(id)
                    }
                }
            }
        }
        """
        #expect(runEffect(source: source).detectedIssues.isEmpty)
    }

    @Test
    func swiftUITaskModifierIsEscaping_idempotentCaller() {
        // SwiftUI `.task { … }` — the trailing closure parses as the trailing
        // closure of a method call whose callee name is "task". Phase 1 treats
        // this as an escape boundary because SwiftUI re-runs the closure on
        // view identity change; the closure is not part of the caller's
        // synchronous body.
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.effect idempotent
        func makeView(_ id: Int) -> some View {
            Text("Hello")
                .task {
                    try? await insert(id)
                }
        }
        """
        #expect(runEffect(source: source).detectedIssues.isEmpty)
    }

    // MARK: - @context replayable caller + escape boundary

    @Test
    func taskBraceIsEscaping_replayableCaller() {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.context replayable
        func handle(_ id: Int) async throws {
            Task.detached {
                try await insert(id)
            }
        }
        """
        #expect(runContext(source: source).detectedIssues.isEmpty)
    }

    @Test
    func swiftUITaskModifierIsEscaping_replayableCaller() {
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.context replayable
        func makeView(_ id: Int) -> some View {
            Text("Hello")
                .task {
                    try? await insert(id)
                }
        }
        """
        #expect(runContext(source: source).detectedIssues.isEmpty)
    }

    // MARK: - Negative regression: plain closures are NOT escaping

    @Test
    func plainClosureIsNotEscaping_flagsThroughClosureBody() throws {
        // A closure literal inside an if/for/let-binding is NOT escaping — the
        // body check must descend into it. This confirms the walker returns
        // false on the first non-escaping FunctionCall ancestor, and more
        // importantly that the "no ancestor call at all" path also stays false.
        let source = """
        /// @lint.effect non_idempotent
        func insert(_ id: Int) async throws {}

        /// @lint.effect idempotent
        func process(_ id: Int) async throws {
            let work = { try await insert(id) }
            try await work()
        }
        """
        let visitor = runEffect(source: source)
        // The body contains a direct call to `insert` inside the closure
        // literal assigned to `work`. Since the closure isn't passed to an
        // escape boundary, the visitor descends into it and fires.
        #expect(visitor.detectedIssues.isEmpty == false)
    }
}

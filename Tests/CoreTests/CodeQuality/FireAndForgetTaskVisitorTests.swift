import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct FireAndForgetTaskVisitorTests {

    private func makeVisitor() -> FireAndForgetTaskVisitor {
        let pattern = FireAndForgetTask().pattern
        return FireAndForgetTaskVisitor(pattern: pattern)
    }

    private func run(_ visitor: FireAndForgetTaskVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsFireAndForgetTask() throws {
        let source = """
        func doSomething() {
            Task {
                await work()
            }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .fireAndForgetTask)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Fire-and-forget"))
    }

    @Test("Detects fire-and-forget variants", arguments: [
        // Bare Task with async call
        """
        Task { await doWork() }
        """,
        // Task with throw — also fire-and-forget
        """
        Task {
            try await riskyWork()
        }
        """,
        // Multiple fire-and-forget tasks
        """
        func sync() {
            Task { await step1() }
            Task { await step2() }
        }
        """
    ])
    func detectsVariant(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty == false)
    }

    // MARK: - Suppression: Result Captured

    @Test("No issue when Task handle is stored", arguments: [
        // let binding
        """
        let task = Task { await doWork() }
        """,
        // var binding
        """
        var task = Task { await doWork() }
        """,
        // .value consumed
        """
        try await Task { try await doWork() }.value
        """,
        // .result consumed
        """
        let result = Task { await doWork() }.result
        """
    ])
    func noIssueWhenResultCaptured(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Does Not Flag Task.detached (covered by TaskDetachedVisitor)

    @Test
    func doesNotFlagTaskDetached() {
        let source = """
        Task.detached { await work() }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Task.isCancelled usage orthogonality

    @Test("Fire-and-forget fires even if cancellation is checked — separate concerns")
    func firesEvenWithCancellationCheck() {
        let source = """
        func fetchData() async {
            guard !Task.isCancelled else { return }
            Task { await doWork() }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        // The cancellation guard is on the outer function, but the Task is still fire-and-forget
        #expect(visitor.detectedIssues.count == 1)
    }
}

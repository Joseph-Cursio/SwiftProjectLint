import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct MissingCancellationCheckVisitorTests {

    private func makeVisitor() -> MissingCancellationCheckVisitor {
        let pattern = MissingCancellationCheck().pattern
        return MissingCancellationCheckVisitor(pattern: pattern)
    }

    private func run(_ visitor: MissingCancellationCheckVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsAsyncFunctionWithTaskAndNoCheck() throws {
        let source = """
        func fetchData() async {
            Task {
                await doWork()
            }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .missingCancellationCheck)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("fetchData"))
        #expect(issue.message.contains("cancellation"))
    }

    @Test("Detects missing cancellation check variants", arguments: [
        // withTaskGroup without check
        """
        func process() async throws {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await doWork() }
            }
        }
        """,
        // withThrowingTaskGroup without check
        """
        func load() async throws {
            try await withThrowingTaskGroup(of: Data.self) { group in
                group.addTask { try await fetch() }
            }
        }
        """,
        // Multiple tasks, still no check
        """
        func sync() async {
            Task { await step1() }
            Task { await step2() }
        }
        """
    ])
    func detectsVariant(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test("No issue when Task.isCancelled is checked", arguments: [
        // guard with isCancelled
        """
        func fetchData() async {
            guard !Task.isCancelled else { return }
            Task { await doWork() }
        }
        """,
        // isCancelled inside the Task closure
        """
        func fetchData() async {
            Task {
                guard !Task.isCancelled else { return }
                await doWork()
            }
        }
        """,
        // checkCancellation used
        """
        func fetchData() async throws {
            try Task.checkCancellation()
            Task { await doWork() }
        }
        """
    ])
    func noIssueWithCancellationCheck(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when function is not async")
    func noIssueForSyncFunction() {
        let source = """
        func fetchData() {
            Task { await doWork() }
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when async function has no Task creation")
    func noIssueForAsyncFunctionWithoutTask() {
        let source = """
        func fetchData() async {
            let result = await doWork()
            _ = result
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for nested function with its own Task and check")
    func noIssueForNestedFunctionWithCheck() {
        let source = """
        func outer() async {
            func inner() async {
                guard !Task.isCancelled else { return }
                Task { await doWork() }
            }
            await inner()
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        // outer has no Task { } directly; inner has the check — no warnings
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Flags outer function that has Task but check is only in nested function")
    func flagsOuterWhenCheckOnlyInNestedFunction() {
        let source = """
        func outer() async {
            Task { await doWork() }
            func helper() async {
                guard !Task.isCancelled else { return }
            }
            await helper()
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        // outer has Task {} but its own body has no check (check is inside nested func)
        #expect(visitor.detectedIssues.count == 1)
    }
}

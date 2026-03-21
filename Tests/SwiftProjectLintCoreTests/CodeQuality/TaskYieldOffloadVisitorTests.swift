import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct TaskYieldOffloadVisitorTests {

    private func makeVisitor() -> TaskYieldOffloadVisitor {
        let pattern = TaskYieldOffloadPatternRegistrar().pattern
        return TaskYieldOffloadVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: TaskYieldOffloadVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsAwaitTaskYield() throws {
        let source = """
        await Task.yield()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .taskYieldOffload)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("Task.yield()"))
    }

    @Test
    func testDetectsTaskYieldWithoutAwait() throws {
        let source = """
        Task.yield()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .taskYieldOffload)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForTaskSleep() {
        let source = """
        await Task.sleep(for: .seconds(1))
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForTaskCheckCancellation() {
        let source = """
        Task.checkCancellation()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForInstanceTaskCancel() {
        let source = """
        task.cancel()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

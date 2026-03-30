import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct TaskYieldOffloadVisitorTests {

    private func makeVisitor() -> TaskYieldOffloadVisitor {
        let pattern = TaskYieldOffload().pattern
        return TaskYieldOffloadVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: TaskYieldOffloadVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Positive Case

    @Test
    func detectsAwaitTaskYield() throws {
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

    @Test("Detects Task.yield variant", arguments: [
        """
        Task.yield()
        """
    ])
    func detectsVariant(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test("No issue for other Task methods", arguments: [
        // Task.sleep
        """
        await Task.sleep(for: .seconds(1))
        """,
        // Task.checkCancellation
        """
        Task.checkCancellation()
        """,
        // Instance task cancel
        """
        task.cancel()
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

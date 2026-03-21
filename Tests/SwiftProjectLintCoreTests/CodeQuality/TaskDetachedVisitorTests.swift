import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct TaskDetachedVisitorTests {

    private func makeVisitor() -> TaskDetachedVisitor {
        let pattern = TaskDetachedPatternRegistrar().pattern
        return TaskDetachedVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: TaskDetachedVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Positive Case

    @Test
    func detectsTaskDetached() throws {
        let source = """
        Task.detached {
            await work()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .taskDetached)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("Task.detached"))
    }

    @Test("Detects Task.detached variant", arguments: [
        """
        Task.detached(priority: .background) {
            await work()
        }
        """
    ])
    func detectsVariant(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test("No issue for non-detached Task usage", arguments: [
        // Plain Task
        """
        Task {
            await work()
        }
        """,
        // Task with priority
        """
        Task(priority: .high) {
            await work()
        }
        """,
        // Unrelated member access
        """
        let result = SomeClass.detached()
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

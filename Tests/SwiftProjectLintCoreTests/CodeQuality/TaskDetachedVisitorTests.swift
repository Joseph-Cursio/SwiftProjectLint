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

    // MARK: - Positive Cases

    @Test
    func testDetectsTaskDetached() throws {
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

    @Test
    func testDetectsTaskDetachedWithPriority() throws {
        let source = """
        Task.detached(priority: .background) {
            await work()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .taskDetached)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForPlainTask() {
        let source = """
        Task {
            await work()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForTaskWithPriority() {
        let source = """
        Task(priority: .high) {
            await work()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForUnrelatedMemberAccess() {
        let source = """
        let result = SomeClass.detached()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

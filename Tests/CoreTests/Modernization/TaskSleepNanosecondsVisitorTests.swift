import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct TaskSleepNanosecondsVisitorTests {

    private func makeVisitor() -> TaskSleepNanosecondsVisitor {
        let pattern = TaskSleepNanoseconds().pattern
        return TaskSleepNanosecondsVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: TaskSleepNanosecondsVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsTaskSleepNanoseconds() throws {
        let source = """
        try await Task.sleep(nanoseconds: 1_000_000_000)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .taskSleepNanoseconds)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("nanoseconds"))
    }

    @Test
    func detectsMultipleOccurrences() {
        let source = """
        try await Task.sleep(nanoseconds: 500_000_000)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test("No issue for modern Task.sleep APIs", arguments: [
        // Duration-based sleep
        "try await Task.sleep(for: .seconds(1))",
        "try await Task.sleep(for: .milliseconds(500))",
        // Thread.sleep is a different rule
        "Thread.sleep(forTimeInterval: 1.0)",
        // Other Task methods
        "Task.cancel()",
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

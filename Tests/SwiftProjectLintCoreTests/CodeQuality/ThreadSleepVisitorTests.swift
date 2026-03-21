import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct ThreadSleepVisitorTests {

    private func makeVisitor() -> ThreadSleepVisitor {
        let pattern = ThreadSleepPatternRegistrar().pattern
        return ThreadSleepVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ThreadSleepVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Property Validation

    @Test
    func detectsThreadSleepWithFullProperties() throws {
        let source = """
        Thread.sleep(forTimeInterval: 1.0)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .threadSleep)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Thread.sleep"))
    }

    // MARK: - Parameterized Positive Cases

    @Test("Detects Thread.sleep variant", arguments: [
        "Thread.sleep(forTimeInterval: 1.0)",
        "Thread.sleep(until: Date().addingTimeInterval(2.0))"
    ])
    func detectsThreadSleepVariant(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsMultipleThreadSleeps() {
        let source = """
        Thread.sleep(forTimeInterval: 0.5)
        Thread.sleep(forTimeInterval: 1.0)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Parameterized Negative Cases

    @Test("No issue for non-Thread.sleep code", arguments: [
        "try await Task.sleep(for: .seconds(1))",
        "let isMain = Thread.isMainThread\nlet current = Thread.current",
        "process.sleep(duration: 5)"
    ])
    func noIssueForNonThreadSleep(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

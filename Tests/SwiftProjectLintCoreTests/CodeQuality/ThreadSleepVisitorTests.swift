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

    // MARK: - Positive Cases

    @Test
    func testDetectsThreadSleep() throws {
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

    @Test
    func testDetectsThreadSleepUntil() throws {
        let source = """
        Thread.sleep(until: Date().addingTimeInterval(2.0))
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func testDetectsMultipleThreadSleeps() throws {
        let source = """
        Thread.sleep(forTimeInterval: 0.5)
        Thread.sleep(forTimeInterval: 1.0)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForTaskSleep() {
        let source = """
        try await Task.sleep(for: .seconds(1))
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForOtherThreadMethods() {
        let source = """
        let isMain = Thread.isMainThread
        let current = Thread.current
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForUnrelatedSleep() {
        let source = """
        process.sleep(duration: 5)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct DispatchMainAsyncVisitorTests {

    private func makeVisitor() -> DispatchMainAsyncVisitor {
        let pattern = DispatchMainAsyncPatternRegistrar().pattern
        return DispatchMainAsyncVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: DispatchMainAsyncVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsDispatchMainAsync() throws {
        let source = """
        DispatchQueue.main.async {
            self.updateUI()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .dispatchMainAsync)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("async"))
        #expect(issue.message.contains("MainActor.run"))
    }

    @Test
    func testDetectsDispatchMainSync() throws {
        let source = """
        DispatchQueue.main.sync {
            self.updateUI()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("sync"))
    }

    @Test
    func testDetectsMultipleCalls() throws {
        let source = """
        DispatchQueue.main.async { self.reload() }
        DispatchQueue.main.sync { self.flush() }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForDispatchGlobalAsync() {
        let source = """
        DispatchQueue.global().async {
            self.doWork()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForMainActorRun() {
        let source = """
        await MainActor.run {
            self.updateUI()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForOtherDispatchQueueUsage() {
        let source = """
        let queue = DispatchQueue(label: "com.app.worker")
        queue.async { self.doWork() }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

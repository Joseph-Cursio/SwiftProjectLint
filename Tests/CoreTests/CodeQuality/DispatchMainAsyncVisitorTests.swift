import Testing
@testable import Core
import SwiftSyntax
import SwiftParser

@Suite
struct DispatchMainAsyncVisitorTests {

    private func makeVisitor() -> DispatchMainAsyncVisitor {
        let pattern = DispatchMainAsync().pattern
        return DispatchMainAsyncVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: DispatchMainAsyncVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Property Validation

    @Test
    func detectsDispatchMainAsyncWithFullProperties() throws {
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

    // MARK: - Parameterized Positive Cases

    @Test("Detects DispatchQueue.main usage", arguments: [
        ("DispatchQueue.main.async {\n    self.updateUI()\n}", "async"),
        ("DispatchQueue.main.sync {\n    self.updateUI()\n}", "sync")
    ])
    func detectsDispatchMainUsage(source: String, expectedSubstring: String) throws {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains(expectedSubstring))
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func detectsMultipleCalls() {
        let source = """
        DispatchQueue.main.async { self.reload() }
        DispatchQueue.main.sync { self.flush() }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Parameterized Negative Cases

    // swiftprojectlint:disable Test Missing Require
    @Test("No issue for non-main dispatch usage", arguments: [
        "DispatchQueue.global().async {\n    self.doWork()\n}",
        "await MainActor.run {\n    self.updateUI()\n}",
        "let queue = DispatchQueue(label: \"com.app.worker\")\nqueue.async { self.doWork() }"
    ])
    func noIssueForNonMainDispatch(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

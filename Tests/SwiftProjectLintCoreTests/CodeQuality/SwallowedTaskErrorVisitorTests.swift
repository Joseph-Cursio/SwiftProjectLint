import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct SwallowedTaskErrorVisitorTests {

    private func makeVisitor() -> SwallowedTaskErrorVisitor {
        let pattern = SwallowedTaskErrorPatternRegistrar().pattern
        return SwallowedTaskErrorVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: SwallowedTaskErrorVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsTaskWithTryNoDocatch() throws {
        let source = """
        Task {
            try await riskyWork()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .swallowedTaskError)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("try"))
    }

    @Test
    func testDetectsTaskWithTryLetFetch() throws {
        let source = """
        Task {
            let data = try await fetch()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .swallowedTaskError)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForTaskWithDoCatch() {
        let source = """
        Task {
            do {
                try await riskyWork()
            } catch {
                print(error)
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForTaskWithoutTry() {
        let source = """
        Task {
            await nonThrowingWork()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForTryOutsideTask() {
        let source = """
        try await riskyWork()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

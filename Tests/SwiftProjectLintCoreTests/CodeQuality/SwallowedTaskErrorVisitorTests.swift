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

    // MARK: - Detailed Positive Case

    @Test
    func detectsTaskWithTryNoDocatch() throws {
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

    @Test("Detects swallowed error variant", arguments: [
        """
        Task {
            let data = try await fetch()
        }
        """
    ])
    func detectsVariant(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test("No issue for proper error handling", arguments: [
        // Task with do-catch
        """
        Task {
            do {
                try await riskyWork()
            } catch {
                print(error)
            }
        }
        """,
        // Task without try
        """
        Task {
            await nonThrowingWork()
        }
        """,
        // try outside Task
        """
        try await riskyWork()
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

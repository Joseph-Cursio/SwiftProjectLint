import Testing
@testable import Core
import SwiftSyntax
import SwiftParser

@Suite
struct AsyncLetUnusedVisitorTests {

    private func makeVisitor() -> AsyncLetUnusedVisitor {
        let pattern = AsyncLetUnused().pattern
        return AsyncLetUnusedVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: AsyncLetUnusedVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Positive Case

    @Test
    func detectsAsyncLetWildcard() throws {
        let source = """
        func example() async {
            async let _ = fetchData()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .asyncLetUnused)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("discarded result"))
    }

    // MARK: - Negative Cases

    // swiftprojectlint:disable Test Missing Require
    @Test("No issue for proper async let usage", arguments: [
        // Named async let
        """
        func example() async {
            async let result = fetchData()
            _ = await result
        }
        """,
        // Non-async let wildcard
        """
        let _ = syncFunc()
        """,
        // Regular variable
        """
        let value = computeResult()
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

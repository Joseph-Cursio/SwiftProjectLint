import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct AsyncLetUnusedVisitorTests {

    private func makeVisitor() -> AsyncLetUnusedVisitor {
        let pattern = AsyncLetUnusedPatternRegistrar().pattern
        return AsyncLetUnusedVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: AsyncLetUnusedVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsAsyncLetWildcard() throws {
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

    @Test
    func testNoIssueForNamedAsyncLet() {
        let source = """
        func example() async {
            async let result = fetchData()
            _ = await result
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForNonAsyncLetWildcard() {
        let source = """
        let _ = syncFunc()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForRegularVariable() {
        let source = """
        let value = computeResult()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct EmptyCatchVisitorTests {

    private func makeVisitor() -> EmptyCatchVisitor {
        let pattern = EmptyCatchPatternRegistrar().pattern
        return EmptyCatchVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: EmptyCatchVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsEmptyCatch() throws {
        let source = """
        do {
            try riskyOperation()
        } catch {
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .emptyCatch)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("Empty catch"))
    }

    @Test
    func testDetectsEmptyCatchWithWhitespace() throws {
        let source = """
        do {
            try loadData()
        } catch {

        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func testDetectsMultipleEmptyCatches() throws {
        let source = """
        do {
            try first()
        } catch {
        }
        do {
            try second()
        } catch {
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForCatchWithPrint() {
        let source = """
        do {
            try riskyOperation()
        } catch {
            print(error)
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForCatchWithLogger() {
        let source = """
        do {
            try riskyOperation()
        } catch {
            logger.error("Failed: \\(error)")
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForCatchWithRethrow() {
        let source = """
        do {
            try riskyOperation()
        } catch {
            throw error
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

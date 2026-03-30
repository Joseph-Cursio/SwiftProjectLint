import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct EmptyCatchVisitorTests {

    private func makeVisitor() -> EmptyCatchVisitor {
        let pattern = EmptyCatch().pattern
        return EmptyCatchVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: EmptyCatchVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Property Validation

    @Test
    func detectsEmptyCatchWithFullProperties() throws {
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

    // MARK: - Parameterized Positive Cases

    @Test("Detects empty catch block", arguments: [
        "do {\n    try riskyOperation()\n} catch {\n}",
        "do {\n    try loadData()\n} catch {\n\n}"
    ])
    func detectsEmptyCatch(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsMultipleEmptyCatches() {
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

    // MARK: - Parameterized Negative Cases

    @Test("No issue for catch block with content", arguments: [
        "do {\n    try riskyOperation()\n} catch {\n    print(error)\n}",
        "do {\n    try riskyOperation()\n} catch {\n    logger.error(\"Failed: \\(error)\")\n}",
        "do {\n    try riskyOperation()\n} catch {\n    throw error\n}"
    ])
    func noIssueForCatchWithContent(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

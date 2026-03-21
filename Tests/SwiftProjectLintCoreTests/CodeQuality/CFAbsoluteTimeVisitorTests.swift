import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct CFAbsoluteTimeVisitorTests {

    private func makeVisitor() -> CFAbsoluteTimeVisitor {
        let pattern = CFAbsoluteTimePatternRegistrar().pattern
        return CFAbsoluteTimeVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: CFAbsoluteTimeVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsCFAbsoluteTimeGetCurrent() throws {
        let source = """
        let start = CFAbsoluteTimeGetCurrent()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .cfAbsoluteTime)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("CFAbsoluteTimeGetCurrent"))
    }

    @Test
    func testDetectsMultipleCalls() throws {
        let source = """
        let start = CFAbsoluteTimeGetCurrent()
        doWork()
        let end = CFAbsoluteTimeGetCurrent()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    @Test
    func testDetectsInExpression() throws {
        let source = """
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForDateNow() {
        let source = """
        let now = Date.now
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForContinuousClock() {
        let source = """
        let clock = ContinuousClock()
        let now = clock.now
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForOtherCFFunctions() {
        let source = """
        let runLoop = CFRunLoopGetCurrent()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

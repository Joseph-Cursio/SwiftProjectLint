import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct CFAbsoluteTimeVisitorTests {

    private func makeVisitor() -> CFAbsoluteTimeVisitor {
        let pattern = CFAbsoluteTime().pattern
        return CFAbsoluteTimeVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: CFAbsoluteTimeVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Property Validation

    @Test
    func detectsCFAbsoluteTimeWithFullProperties() throws {
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

    // MARK: - Parameterized Positive Cases

    @Test("Detects CFAbsoluteTimeGetCurrent usage", arguments: [
        "let start = CFAbsoluteTimeGetCurrent()",
        "let elapsed = CFAbsoluteTimeGetCurrent() - startTime"
    ])
    func detectsCFAbsoluteTimeUsage(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsMultipleCalls() {
        let source = """
        let start = CFAbsoluteTimeGetCurrent()
        doWork()
        let end = CFAbsoluteTimeGetCurrent()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Parameterized Negative Cases

    @Test("No issue for non-CFAbsoluteTime code", arguments: [
        "let now = Date.now",
        "let clock = ContinuousClock()\nlet now = clock.now",
        "let runLoop = CFRunLoopGetCurrent()"
    ])
    func noIssueForNonCFAbsoluteTime(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

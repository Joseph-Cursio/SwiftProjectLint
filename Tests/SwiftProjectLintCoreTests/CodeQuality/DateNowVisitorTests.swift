import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct DateNowVisitorTests {

    private func makeVisitor() -> DateNowVisitor {
        let pattern = DateNowPatternRegistrar().pattern
        return DateNowVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: DateNowVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsDateInit() throws {
        let source = """
        let now = Date()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .dateNow)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("Date.now"))
    }

    @Test
    func testDetectsDateInitInExpression() throws {
        let source = """
        let elapsed = Date().timeIntervalSince(lastRun)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func testDetectsDateInitInAssignment() throws {
        let source = """
        lastRunDate = Date()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func testDetectsMultipleDateInits() throws {
        let source = """
        let start = Date()
        let end = Date()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
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
    func testNoIssueForDateWithArguments() {
        let source = """
        let date = Date(timeIntervalSince1970: 0)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForOtherInitializers() {
        let source = """
        let formatter = DateFormatter()
        let url = URL(string: "https://example.com")
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForDateDistantFuture() {
        let source = """
        let future = Date.distantFuture
        let past = Date.distantPast
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct DateNowVisitorTests {

    private func makeVisitor() -> DateNowVisitor {
        let pattern = DateNow().pattern
        return DateNowVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: DateNowVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Property Validation

    @Test
    func detectsDateInitWithFullProperties() throws {
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

    // MARK: - Parameterized Positive Cases

    @Test("Detects Date() initializer", arguments: [
        "let now = Date()",
        "let elapsed = Date().timeIntervalSince(lastRun)",
        "lastRunDate = Date()"
    ])
    func detectsDateInit(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsMultipleDateInits() {
        let source = """
        let start = Date()
        let end = Date()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Parameterized Negative Cases

    @Test("No issue for non-Date() code", arguments: [
        "let now = Date.now",
        "let date = Date(timeIntervalSince1970: 0)",
        "let formatter = DateFormatter()\nlet url = URL(string: \"https://example.com\")",
        "let future = Date.distantFuture\nlet past = Date.distantPast"
    ])
    func noIssueForNonDateInit(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

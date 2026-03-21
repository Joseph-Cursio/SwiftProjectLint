import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct ForceUnwrapVisitorTests {

    private func makeVisitor() -> ForceUnwrapVisitor {
        let pattern = ForceUnwrapPatternRegistrar().pattern
        return ForceUnwrapVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ForceUnwrapVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Property Validation

    @Test
    func detectsForceUnwrapWithFullProperties() throws {
        let source = """
        let value = optional!
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .forceUnwrap)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("Force unwrap"))
    }

    // MARK: - Parameterized Positive Cases

    @Test("Detects force unwrap expression", arguments: [
        "let value = optional!",
        "let value = foo.bar!.baz"
    ])
    func detectsForceUnwrap(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsMultipleForceUnwraps() {
        let source = """
        let first = optA!
        let second = optB!
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Parameterized Negative Cases

    @Test("No issue for safe optional handling", arguments: [
        "let value: String! = \"hello\"",
        "let value = foo?.bar",
        "let value = optional ?? \"default\""
    ])
    func noIssueForSafeOptionalHandling(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

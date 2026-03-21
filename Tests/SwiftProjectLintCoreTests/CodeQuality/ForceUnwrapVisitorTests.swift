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

    // MARK: - Positive Cases

    @Test
    func testDetectsForceUnwrap() throws {
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

    @Test
    func testDetectsChainedForceUnwrap() throws {
        let source = """
        let value = foo.bar!.baz
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func testDetectsMultipleForceUnwraps() throws {
        let source = """
        let first = optA!
        let second = optB!
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForImplicitlyUnwrappedOptionalDeclaration() {
        let source = """
        let value: String! = "hello"
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForOptionalChaining() {
        let source = """
        let value = foo?.bar
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForNilCoalescing() {
        let source = """
        let value = optional ?? "default"
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

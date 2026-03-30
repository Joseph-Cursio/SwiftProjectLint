import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct LegacyRandomVisitorTests {

    private func makeVisitor() -> LegacyRandomVisitor {
        let pattern = LegacyRandom().pattern
        return LegacyRandomVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: LegacyRandomVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Property Validation

    @Test
    func detectsArc4randomWithFullProperties() throws {
        let source = """
        let value = arc4random()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .legacyRandom)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("arc4random"))
    }

    // MARK: - Parameterized Positive Cases

    @Test("Detects legacy random call", arguments: [
        ("let value = arc4random()", "arc4random"),
        ("let value = arc4random_uniform(10)", "arc4random_uniform"),
        ("let value = drand48()", "drand48")
    ])
    func detectsLegacyRandomCall(source: String, expectedSubstring: String) throws {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains(expectedSubstring))
    }

    @Test
    func detectsMultipleLegacyRandomCalls() {
        let source = """
        let first = arc4random()
        let second = arc4random_uniform(100)
        let third = drand48()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 3)
    }

    // MARK: - Parameterized Negative Cases

    @Test("No issue for modern random API", arguments: [
        "let value = Int.random(in: 0..<10)",
        "let coin = Bool.random()",
        "let value = Double.random(in: 0.0...1.0)"
    ])
    func noIssueForModernRandom(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

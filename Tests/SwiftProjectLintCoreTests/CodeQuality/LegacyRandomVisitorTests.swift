import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct LegacyRandomVisitorTests {

    private func makeVisitor() -> LegacyRandomVisitor {
        let pattern = LegacyRandomPatternRegistrar().pattern
        return LegacyRandomVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: LegacyRandomVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsArc4random() throws {
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

    @Test
    func testDetectsArc4randomUniform() throws {
        let source = """
        let value = arc4random_uniform(10)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("arc4random_uniform"))
    }

    @Test
    func testDetectsDrand48() throws {
        let source = """
        let value = drand48()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("drand48"))
    }

    @Test
    func testDetectsMultipleLegacyRandomCalls() throws {
        let source = """
        let first = arc4random()
        let second = arc4random_uniform(100)
        let third = drand48()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 3)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForIntRandom() {
        let source = """
        let value = Int.random(in: 0..<10)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForBoolRandom() {
        let source = """
        let coin = Bool.random()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForDotRandom() {
        let source = """
        let value = Double.random(in: 0.0...1.0)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

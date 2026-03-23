import Testing
import SwiftSyntax
import SwiftParser
@testable import Core

@Suite
struct ExpectNegationVisitorTests {

    private func makeVisitor() -> ExpectNegationVisitor {
        ExpectNegationVisitor(patternCategory: .codeQuality)
    }

    private func run(_ visitor: ExpectNegationVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Detailed Positive Case

    @Test
    func detectsNegatedBoolVariable() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        #expect(!isVisible)
        """)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .expectNegation)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("isVisible"))
        #expect(issue.message.contains("== false"))
    }

    @Test("Detects negation variant", arguments: [
        (
            """
            #expect(!items.isEmpty)
            """,
            "items.isEmpty"
        )
    ] as [(String, String)])
    func detectsVariant(source: String, expected: String) throws {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains(expected))
    }

    // Unique: validates multi-issue count
    @Test
    func detectsMultipleNegations() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        #expect(!a)
        #expect(!b.isEmpty)
        """)
        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test("No issue for valid patterns", arguments: [
        // expect with == false
        """
        #expect(isVisible == false)
        """,
        // Positive conditions
        """
        #expect(isVisible)
        #expect(count == 3)
        #expect(items.isEmpty)
        """,
        // #require macro (different macro)
        """
        let _ = try #require(!isVisible)
        """,
        // Negation outside #expect
        """
        let flag = !isVisible
        if !isLoading { }
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

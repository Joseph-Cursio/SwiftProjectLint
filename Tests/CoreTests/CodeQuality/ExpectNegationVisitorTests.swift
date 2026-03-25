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

    // MARK: - #expect Positive Cases

    @Test
    func detectsNegatedBoolInExpect() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        #expect(!isVisible)
        """)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .macroNegation)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("isVisible"))
        #expect(issue.message.contains("#expect"))
        #expect(issue.message.contains("== false"))
    }

    @Test
    func detectsNegatedMemberAccessInExpect() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        #expect(!items.isEmpty)
        """)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("items.isEmpty"))
    }

    // MARK: - #require Positive Cases

    @Test
    func detectsNegatedBoolInRequire() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        let _ = try #require(!isVisible)
        """)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .macroNegation)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("isVisible"))
        #expect(issue.message.contains("#require"))
        #expect(issue.message.contains("== false"))
    }

    @Test
    func detectsNegatedMemberAccessInRequire() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        let _ = try #require(!items.isEmpty)
        """)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("items.isEmpty"))
        #expect(issue.message.contains("#require"))
    }

    // MARK: - Multiple Detections

    @Test
    func detectsMultipleNegationsAcrossMacros() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        #expect(!flagA)
        let _ = try #require(!flagB)
        #expect(!flagC.isEmpty)
        """)
        #expect(visitor.detectedIssues.count == 3)
    }

    // MARK: - Negative Cases

    @Test("No issue for valid patterns", arguments: [
        // expect with == false
        """
        #expect(isVisible == false)
        """,
        // require with == false
        """
        let _ = try #require(isVisible == false)
        """,
        // Positive conditions
        """
        #expect(isVisible)
        #expect(count == 3)
        #expect(items.isEmpty)
        """,
        // Positive require
        """
        let val = try #require(optionalValue)
        """,
        // Negation outside macros
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

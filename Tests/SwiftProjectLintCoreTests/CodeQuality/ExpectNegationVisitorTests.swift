import Testing
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

struct ExpectNegationVisitorTests {

    private func makeVisitor() -> ExpectNegationVisitor {
        ExpectNegationVisitor(patternCategory: .codeQuality)
    }

    private func run(_ visitor: ExpectNegationVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Detection

    @Test func detectsNegatedBoolVariable() throws {
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

    @Test func detectsNegatedMethodCall() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        #expect(!items.isEmpty)
        """)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("items.isEmpty"))
    }

    @Test func detectsMultipleNegations() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        #expect(!a)
        #expect(!b.isEmpty)
        """)
        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - No false positives

    @Test func ignoresExpectWithEqualsFalse() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        #expect(isVisible == false)
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test func ignoresExpectWithPositiveCondition() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        #expect(isVisible)
        #expect(count == 3)
        #expect(items.isEmpty)
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test func ignoresRequireMacro() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        let _ = try #require(!isVisible)
        """)
        // #require is a different macro — visitor only targets #expect
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test func ignoresNegationOutsideExpect() throws {
        let visitor = makeVisitor()
        run(visitor, source: """
        let flag = !isVisible
        if !isLoading { }
        """)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

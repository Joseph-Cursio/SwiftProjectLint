import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct LegacyStringFormatVisitorTests {

    private func makeVisitor() -> LegacyStringFormatVisitor {
        let pattern = LegacyStringFormat().pattern
        return LegacyStringFormatVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: LegacyStringFormatVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsStringFormat() throws {
        let source = """
        let label = String(format: "%.2f", value)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .legacyStringFormat)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("String(format:)"))
    }

    @Test
    func detectsStringFormatWithMultipleArgs() throws {
        let source = """
        let text = String(format: "%d of %d items", count, total)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsMultipleOccurrences() {
        let source = """
        let a = String(format: "%.1f km", distance)
        let b = String(format: "%02d:%02d", minutes, seconds)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test("No issue for modern string formatting", arguments: [
        // String interpolation
        "let s = \"\\(value)\"",
        // FormatStyle
        "let s = value.formatted(.number.precision(.fractionLength(2)))",
        // String init without format label
        "let s = String(describing: value)",
        "let s = String(data: data, encoding: .utf8)",
        // String(localized:) — not C-style
        "let s = String(localized: \"hello\")",
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

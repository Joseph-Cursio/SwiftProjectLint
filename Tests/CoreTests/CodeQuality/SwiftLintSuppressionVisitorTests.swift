import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct SwiftLintSuppressionVisitorTests {

    private func makeVisitor() -> SwiftLintSuppressionVisitor {
        let pattern = SwiftLintSuppression().pattern
        return SwiftLintSuppressionVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: SwiftLintSuppressionVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Property Validation

    @Test
    func detectsBlockDisableWithFullProperties() throws {
        let source = """
        // swiftlint:disable force_cast
        let val = foo as! Bar
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .swiftlintSuppression)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("swiftlint:disable"))
        #expect(issue.message.contains("force_cast"))
    }

    // MARK: - Parameterized Positive Cases

    @Test("Detects suppression comment", arguments: [
        ("// swiftlint:disable force_cast\nlet val = foo as! Bar", "swiftlint:disable", "force_cast"),
        ("// swiftlint:disable:next line_length\nlet val = 1", "swiftlint:disable:next", "line_length"),
        ("// swiftlint:disable force_unwrapping\nlet val = 1", "swiftlint:disable", "force_unwrapping"),
        ("/* swiftlint:disable identifier_name */\nlet val = 1", "swiftlint:disable", "identifier_name")
    ])
    func detectsSuppressionComment(source: String, directive: String, rule: String) throws {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .swiftlintSuppression)
        #expect(issue.message.contains(directive))
        #expect(issue.message.contains(rule))
    }

    // MARK: - Multiple Rules on One Line

    @Test
    func detectsMultipleRulesOnOneLine() throws {
        let source = """
        // swiftlint:disable force_cast force_unwrapping line_length
        let val = 1
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 3)
        let messages = visitor.detectedIssues.map(\.message)
        #expect(messages.contains { $0.contains("force_cast") })
        #expect(messages.contains { $0.contains("force_unwrapping") })
        #expect(messages.contains { $0.contains("line_length") })
    }

    // MARK: - Parameterized Negative Cases

    @Test("No issue for non-suppression comment", arguments: [
        "// This is a normal comment\nlet value = 42",
        "// swiftprojectlint:disable force-try\nlet val = 1",
        "let disable = \"swiftlint:disable\"\nlet val = 1",
        "// swiftlint:enable force_cast\nlet val = 1"
    ])
    func noIssueForNonSuppressionComment(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

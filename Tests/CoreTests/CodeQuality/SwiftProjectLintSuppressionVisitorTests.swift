import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct SwiftProjectLintSuppressionVisitorTests {

    private func makeVisitor() -> SwiftProjectLintSuppressionVisitor {
        let pattern = SwiftProjectLintSuppression().pattern
        return SwiftProjectLintSuppressionVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: SwiftProjectLintSuppressionVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Property Validation

    @Test
    func detectsBlockDisableWithFullProperties() throws {
        let source = """
        // swiftprojectlint:disable force-try
        let val = try! something()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .swiftprojectlintSuppression)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("swiftprojectlint:disable"))
        #expect(issue.message.contains("force-try"))
    }

    // MARK: - Parameterized Positive Cases

    @Test("Detects suppression comment", arguments: [
        ("// swiftprojectlint:disable force-try\nlet val = 1",
         "swiftprojectlint:disable", "force-try"),
        ("// swiftprojectlint:disable:next line-length\nlet val = 1",
         "swiftprojectlint:disable:next", "line-length"),
        ("// swiftprojectlint:disable:this could-be-private\nlet val = 1",
         "swiftprojectlint:disable:this", "could-be-private"),
        ("/* swiftprojectlint:disable magic-number */\nlet val = 1",
         "swiftprojectlint:disable", "magic-number")
    ])
    func detectsSuppressionComment(
        source: String, directive: String, rule: String
    ) throws {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .swiftprojectlintSuppression)
        #expect(issue.message.contains(directive))
        #expect(issue.message.contains(rule))
    }

    // MARK: - Multiple Rules on One Line

    @Test
    func detectsMultipleRulesOnOneLine() throws {
        let source = """
        // swiftprojectlint:disable force-try force-unwrap magic-number
        let val = 1
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 3)
        let messages = visitor.detectedIssues.map(\.message)
        #expect(messages.contains { $0.contains("force-try") })
        #expect(messages.contains { $0.contains("force-unwrap") })
        #expect(messages.contains { $0.contains("magic-number") })
    }

    // MARK: - Parameterized Negative Cases

    @Test("No issue for non-suppression comment", arguments: [
        "// This is a normal comment\nlet value = 42",
        "// swiftlint:disable force_cast\nlet val = 1",
        "let disable = \"swiftprojectlint:disable\"\nlet val = 1",
        "// swiftprojectlint:enable force-try\nlet val = 1"
    ])
    func noIssueForNonSuppressionComment(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

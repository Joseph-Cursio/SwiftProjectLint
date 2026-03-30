import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct TodoCommentVisitorTests {

    private func makeVisitor() -> TodoCommentVisitor {
        let pattern = TodoComment().pattern
        return TodoCommentVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: TodoCommentVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Property Validation

    @Test
    func detectsTodoCommentWithFullProperties() throws {
        let source = """
        // TODO: fix this later
        let value = 42
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .todoComment)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("TODO"))
    }

    // MARK: - Parameterized Positive Cases

    @Test("Detects marker comment", arguments: [
        ("// TODO: fix this later\nlet value = 42", "TODO"),
        ("// FIXME: broken logic here\nfunc calculate() -> Int { return 0 }", "FIXME"),
        ("// HACK: workaround for compiler bug\nlet hack = true", "HACK"),
        ("/* TODO: refactor this entire module */\nstruct MyModule {}", "TODO")
    ])
    func detectsMarkerComment(source: String, expectedSubstring: String) throws {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .todoComment)
        #expect(issue.message.contains(expectedSubstring))
    }

    // MARK: - Parameterized Negative Cases

    @Test("No issue for non-marker comment", arguments: [
        "// This is a normal comment\nlet value = 42",
        "let todo = \"item\"",
        "// The todo list view shows all items\nlet items: [String] = []"
    ])
    func noIssueForNonMarkerComment(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

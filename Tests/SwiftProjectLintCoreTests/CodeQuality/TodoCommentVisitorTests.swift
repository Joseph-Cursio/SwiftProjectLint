import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct TodoCommentVisitorTests {

    private func makeVisitor() -> TodoCommentVisitor {
        let pattern = TodoCommentPatternRegistrar().pattern
        return TodoCommentVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: TodoCommentVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsTodoComment() throws {
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

    @Test
    func testDetectsFixmeComment() throws {
        let source = """
        // FIXME: broken logic here
        func calculate() -> Int { return 0 }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .todoComment)
        #expect(issue.message.contains("FIXME"))
    }

    @Test
    func testDetectsHackComment() throws {
        let source = """
        // HACK: workaround for compiler bug
        let hack = true
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .todoComment)
        #expect(issue.message.contains("HACK"))
    }

    @Test
    func testDetectsBlockCommentTodo() throws {
        let source = """
        /* TODO: refactor this entire module */
        struct MyModule {}
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .todoComment)
        #expect(issue.message.contains("TODO"))
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForNormalComment() {
        let source = """
        // This is a normal comment
        let value = 42
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForTodoInVariableName() {
        let source = """
        let todo = "item"
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForTodoInCommentWithoutColon() {
        let source = """
        // The todo list view shows all items
        let items: [String] = []
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

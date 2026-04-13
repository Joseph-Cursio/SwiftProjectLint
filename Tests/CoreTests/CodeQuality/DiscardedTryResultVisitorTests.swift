import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct DiscardedTryResultVisitorTests {

    private func makeVisitor() -> DiscardedTryResultVisitor {
        DiscardedTryResultVisitor(pattern: DiscardedTryResult().pattern)
    }

    private func run(_ visitor: DiscardedTryResultVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Positive Cases

    @Test
    func detectsBareDiscardedTryQuestion() throws {
        let source = """
        func doWork() {
            try? riskyCall()
        }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .discardedTryResult)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("discarded"))
    }

    @Test("Detects bare try? in various contexts", arguments: [
        // Top-level expression statement
        "try? save()",
        // Inside a function body
        "func f() { try? delete() }",
        // In a loop
        "for item in items { try? process(item) }"
    ])
    func detectsVariant(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty == false)
    }

    // MARK: - Negative Cases

    @Test("No issue when try? result is used", arguments: [
        // Assigned to let
        "let x = try? call()",
        // Assigned to var
        "var x = try? call()",
        // Used in guard let
        "guard let x = try? call() else { return }",
        // Used in if let
        "if let x = try? call() { use(x) }",
        // Passed as argument
        "process(try? call())",
        // Explicit discard — developer intent is clear
        "_ = try? call()"
    ])
    func noIssueWhenResultUsed(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for bare try or try!")
    func noIssueForOtherTryForms() {
        let visitor = makeVisitor()
        run(visitor, source: "try call()")
        #expect(visitor.detectedIssues.isEmpty)

        let visitor2 = makeVisitor()
        run(visitor2, source: "try! call()")
        #expect(visitor2.detectedIssues.isEmpty)
    }
}

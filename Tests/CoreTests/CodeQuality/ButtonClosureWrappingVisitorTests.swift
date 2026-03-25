import Testing
@testable import Core
import SwiftSyntax
import SwiftParser

@Suite
struct ButtonClosureWrappingVisitorTests {

    private func makeVisitor() -> ButtonClosureWrappingVisitor {
        let pattern = ButtonClosureWrapping().pattern
        return ButtonClosureWrappingVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ButtonClosureWrappingVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Positive Case

    @Test
    func detectsSingleCallInTrailingClosure() throws {
        let source = """
        Button("Save") { doSomething() }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .buttonClosureWrapping)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("doSomething()"))
    }

    // Unique: checks suggestion property
    @Test
    func detectsDismissCall() throws {
        let source = """
        Button("Cancel") { dismiss() }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("dismiss()"))
        #expect(issue.suggestion?.contains("dismiss") == true)
    }

    // MARK: - Negative Cases

    // swiftprojectlint:disable Test Missing Require
    @Test("No issue for valid button patterns", arguments: [
        // Call with arguments
        """
        Button("Save") { doSomething(with: value) }
        """,
        // Member access
        """
        Button("Save") { viewModel.save() }
        """,
        // Multiple statements
        """
        Button("Save") {
            first()
            second()
        }
        """,
        // Action parameter
        """
        Button("Save", action: doSomething)
        """,
        // Label form
        """
        Button { doSomething() } label: { Text("Save") }
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

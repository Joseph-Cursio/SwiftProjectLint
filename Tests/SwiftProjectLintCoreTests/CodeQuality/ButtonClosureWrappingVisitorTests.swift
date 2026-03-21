import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct ButtonClosureWrappingVisitorTests {

    private func makeVisitor() -> ButtonClosureWrappingVisitor {
        let pattern = ButtonClosureWrappingPatternRegistrar().pattern
        return ButtonClosureWrappingVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ButtonClosureWrappingVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsSingleCallInTrailingClosure() throws {
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

    @Test
    func testDetectsDismissCall() throws {
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

    @Test
    func testNoIssueForCallWithArguments() {
        let source = """
        Button("Save") { doSomething(with: value) }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForMemberAccess() {
        let source = """
        Button("Save") { viewModel.save() }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForMultipleStatements() {
        let source = """
        Button("Save") {
            first()
            second()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForActionParameter() {
        let source = """
        Button("Save", action: doSomething)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForLabelForm() {
        let source = """
        Button { doSomething() } label: { Text("Save") }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

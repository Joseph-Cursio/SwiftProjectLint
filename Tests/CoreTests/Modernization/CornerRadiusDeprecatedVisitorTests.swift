import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct CornerRadiusDeprecatedVisitorTests {

    private func makeVisitor() -> CornerRadiusDeprecatedVisitor {
        let pattern = CornerRadiusDeprecated().pattern
        return CornerRadiusDeprecatedVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: CornerRadiusDeprecatedVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsCornerRadius() throws {
        let source = """
        RoundedRectangle(cornerRadius: 12)
            .cornerRadius(8)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .cornerRadiusDeprecated)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("cornerRadius"))
    }

    @Test
    func detectsCornerRadiusOnView() throws {
        let source = """
        Text("Hello")
            .padding()
            .background(.blue)
            .cornerRadius(10)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsMultipleOccurrences() {
        let source = """
        Text("A").cornerRadius(8)
        Text("B").cornerRadius(12)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test("No issue for modern clipShape APIs", arguments: [
        "Text(\"Hello\").clipShape(.rect(cornerRadius: 10))",
        "Text(\"Hello\").clipShape(RoundedRectangle(cornerRadius: 10))",
        "Text(\"Hello\").clipShape(Circle())",
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

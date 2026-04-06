import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct ForegroundColorDeprecatedVisitorTests {

    private func makeVisitor() -> ForegroundColorDeprecatedVisitor {
        let pattern = ForegroundColorDeprecated().pattern
        return ForegroundColorDeprecatedVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ForegroundColorDeprecatedVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsForegroundColor() throws {
        let source = """
        Text("Hello")
            .foregroundColor(.red)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .foregroundColorDeprecated)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("foregroundColor"))
    }

    @Test
    func detectsForegroundColorWithCustomColor() throws {
        let source = """
        Image(systemName: "star")
            .foregroundColor(Color.accentColor)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsMultipleOccurrences() {
        let source = """
        Text("Hello").foregroundColor(.blue)
        Text("World").foregroundColor(.green)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test("No issue for modern foregroundStyle", arguments: [
        "Text(\"Hello\").foregroundStyle(.red)",
        "Text(\"Hello\").foregroundStyle(.linearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom))",
        "Text(\"Hello\").foregroundStyle(.secondary)"
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

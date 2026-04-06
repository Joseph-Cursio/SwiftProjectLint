import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct AnyViewUsageVisitorTests {

    private func makeVisitor() -> AnyViewUsageVisitor {
        let pattern = AnyViewUsage().pattern
        return AnyViewUsageVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: AnyViewUsageVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsAnyViewWrappingText() throws {
        let source = """
        var body: some View {
            AnyView(Text("Hello"))
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .anyViewUsage)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("AnyView"))
    }

    @Test
    func detectsAnyViewInConditional() throws {
        let source = """
        var body: some View {
            if condition {
                return AnyView(Text("A"))
            } else {
                return AnyView(Image(systemName: "star"))
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    @Test
    func detectsAnyViewInFunction() throws {
        let source = """
        func makeView() -> AnyView {
            AnyView(VStack {
                Text("Hello")
                Text("World")
            })
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsMultipleOccurrences() {
        let source = """
        AnyView(Text("A"))
        AnyView(Text("B"))
        AnyView(Text("C"))
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 3)
    }

    // MARK: - Negative Cases

    @Test("No issue for ViewBuilder and generic patterns", arguments: [
        // @ViewBuilder function
        """
        @ViewBuilder
        func makeView() -> some View {
            if condition {
                Text("A")
            } else {
                Image(systemName: "star")
            }
        }
        """,
        // Regular view composition
        """
        var body: some View {
            VStack {
                Text("Hello")
                Image(systemName: "star")
            }
        }
        """,
        // Type containing "AnyView" in name but not the type itself
        "let label = \"AnyViewExample\""
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

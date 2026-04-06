import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct ScrollViewReaderDeprecatedVisitorTests {

    private func makeVisitor() -> ScrollViewReaderDeprecatedVisitor {
        let pattern = ScrollViewReaderDeprecated().pattern
        return ScrollViewReaderDeprecatedVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ScrollViewReaderDeprecatedVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsScrollViewReader() throws {
        let source = """
        ScrollViewReader { proxy in
            ScrollView {
                ForEach(items) { item in
                    Text(item.name).id(item.id)
                }
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .scrollViewReaderDeprecated)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("ScrollViewReader"))
    }

    @Test
    func detectsMultipleOccurrences() {
        let source = """
        ScrollViewReader { proxy in
            ScrollView { Text("A") }
        }
        ScrollViewReader { proxy in
            ScrollView { Text("B") }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test("No issue for modern scroll position APIs", arguments: [
        // Plain ScrollView
        """
        ScrollView {
            Text("Hello")
        }
        """,
        // scrollPosition modifier
        """
        ScrollView {
            ForEach(items) { item in Text(item.name) }
        }
        .scrollPosition(id: $scrolledID)
        """,
        // Other view types
        "List { Text(\"Hello\") }"
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

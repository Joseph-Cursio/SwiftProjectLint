import Testing
@testable import Core
import SwiftSyntax
import SwiftParser

@Suite
struct NavigationViewDeprecatedVisitorTests {

    private func makeVisitor() -> NavigationViewDeprecatedVisitor {
        let pattern = NavigationViewDeprecated().pattern
        return NavigationViewDeprecatedVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: NavigationViewDeprecatedVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsNavigationView() throws {
        let source = """
        NavigationView {
            Text("Hello")
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .navigationViewDeprecated)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("NavigationView"))
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func detectsNavigationViewWithMultipleChildren() {
        let source = """
        NavigationView {
            List {
                Text("Item 1")
                Text("Item 2")
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func detectsMultipleNavigationViews() {
        let source = """
        NavigationView {
            Text("First")
        }
        NavigationView {
            Text("Second")
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    // swiftprojectlint:disable Test Missing Require
    @Test("No issue for modern navigation APIs", arguments: [
        // NavigationStack
        """
        NavigationStack {
            Text("Hello")
        }
        """,
        // NavigationSplitView
        """
        NavigationSplitView {
            List {
                Text("Sidebar")
            }
        } detail: {
            Text("Detail")
        }
        """,
        // Other views
        """
        VStack {
            Text("Hello")
        }
        TabView {
            Text("Tab 1")
        }
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

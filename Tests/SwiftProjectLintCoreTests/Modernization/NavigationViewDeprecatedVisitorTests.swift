import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct NavigationViewDeprecatedVisitorTests {

    private func makeVisitor() -> NavigationViewDeprecatedVisitor {
        let pattern = NavigationViewDeprecatedPatternRegistrar().pattern
        return NavigationViewDeprecatedVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: NavigationViewDeprecatedVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsNavigationView() throws {
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

    @Test
    func testDetectsNavigationViewWithMultipleChildren() throws {
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

    @Test
    func testDetectsMultipleNavigationViews() throws {
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

    @Test
    func testNoIssueForNavigationStack() {
        let source = """
        NavigationStack {
            Text("Hello")
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForNavigationSplitView() {
        let source = """
        NavigationSplitView {
            List {
                Text("Sidebar")
            }
        } detail: {
            Text("Detail")
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForOtherViews() {
        let source = """
        VStack {
            Text("Hello")
        }
        TabView {
            Text("Tab 1")
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

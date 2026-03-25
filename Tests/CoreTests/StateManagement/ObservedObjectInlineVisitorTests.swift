import Testing
@testable import Core
import SwiftSyntax
import SwiftParser

@Suite
struct ObservedObjectInlineVisitorTests {

    private func makeVisitor() -> ObservedObjectInlineVisitor {
        let pattern = ObservedObjectInline().pattern
        return ObservedObjectInlineVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ObservedObjectInlineVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsObservedObjectWithInlineInit() throws {
        let source = """
        struct MyView: View {
            @ObservedObject var viewModel = ViewModel()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .observedObjectInline)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("ObservedObject"))
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func detectsObservedObjectWithDifferentType() {
        let source = """
        struct SettingsView: View {
            @ObservedObject var store = DataStore()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test
    func detectsMultipleInlineObservedObjects() {
        let source = """
        struct MyView: View {
            @ObservedObject var viewModel = ViewModel()
            @ObservedObject var store = DataStore()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    // swiftprojectlint:disable Test Missing Require
    @Test("No issue for non-inline ObservedObject", arguments: [
        // ObservedObject without initializer
        """
        struct MyView: View {
            @ObservedObject var viewModel: ViewModel
        }
        """,
        // StateObject (correct for inline init)
        """
        struct MyView: View {
            @StateObject var viewModel = ViewModel()
        }
        """,
        // @State variable
        """
        struct MyView: View {
            @State var count = 0
        }
        """,
        // Plain variable
        """
        struct MyView: View {
            var viewModel: ViewModel
        }
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

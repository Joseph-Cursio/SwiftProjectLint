import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct ObservedObjectInlineVisitorTests {

    private func makeVisitor() -> ObservedObjectInlineVisitor {
        let pattern = ObservedObjectInlinePatternRegistrar().pattern
        return ObservedObjectInlineVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ObservedObjectInlineVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsObservedObjectWithInlineInit() throws {
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

    @Test
    func testDetectsObservedObjectWithDifferentType() throws {
        let source = """
        struct SettingsView: View {
            @ObservedObject var store = DataStore()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func testDetectsMultipleInlineObservedObjects() throws {
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

    @Test
    func testNoIssueForObservedObjectWithoutInitializer() {
        let source = """
        struct MyView: View {
            @ObservedObject var viewModel: ViewModel
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForStateObject() {
        let source = """
        struct MyView: View {
            @StateObject var viewModel = ViewModel()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForStateVariable() {
        let source = """
        struct MyView: View {
            @State var count = 0
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForPlainVariable() {
        let source = """
        struct MyView: View {
            var viewModel: ViewModel
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct LegacyObservableObjectVisitorTests {

    private func makeVisitor() -> LegacyObservableObjectVisitor {
        let pattern = LegacyObservableObjectPatternRegistrar().pattern
        return LegacyObservableObjectVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: LegacyObservableObjectVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsStateObject() throws {
        let source = """
        struct ContentView: View {
            @StateObject var viewModel = ViewModel()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .legacyObservableObject)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("StateObject"))
        #expect(issue.suggestion?.contains("@State") == true)
    }

    @Test
    func testDetectsObservedObject() throws {
        let source = """
        struct DetailView: View {
            @ObservedObject var model: Model
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .legacyObservableObject)
        #expect(issue.message.contains("ObservedObject"))
        #expect(issue.suggestion?.contains("@Bindable") == true)
    }

    @Test
    func testDetectsEnvironmentObject() throws {
        let source = """
        struct SettingsView: View {
            @EnvironmentObject var settings: Settings
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .legacyObservableObject)
        #expect(issue.message.contains("EnvironmentObject"))
        #expect(issue.suggestion?.contains("@Environment") == true)
    }

    @Test
    func testDetectsPublished() throws {
        let source = """
        class ViewModel: ObservableObject {
            @Published var count = 0
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .legacyObservableObject)
        #expect(issue.message.contains("Published"))
        #expect(issue.suggestion?.contains("remove") == true)
    }

    @Test
    func testDetectsMultipleLegacyAttributes() throws {
        let source = """
        class ViewModel: ObservableObject {
            @Published var name = ""
            @Published var count = 0
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForState() {
        let source = """
        struct ContentView: View {
            @State var count = 0
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForEnvironment() {
        let source = """
        struct ContentView: View {
            @Environment(\\.dismiss) var dismiss
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForBindable() {
        let source = """
        struct DetailView: View {
            @Bindable var model: Model
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForObservableMacro() {
        let source = """
        @Observable
        class AppState {
            var count = 0
            var name = ""
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

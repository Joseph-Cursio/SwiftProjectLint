import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct LegacyObservableObjectVisitorTests {

    private func makeVisitor() -> LegacyObservableObjectVisitor {
        let pattern = LegacyObservableObject().pattern
        return LegacyObservableObjectVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: LegacyObservableObjectVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test("Detects legacy observable attribute", arguments: [
        ("""
        struct ContentView: View {
            @StateObject var viewModel = ViewModel()
        }
        """, "StateObject", "@State"),
        ("""
        struct DetailView: View {
            @ObservedObject var model: Model
        }
        """, "ObservedObject", "@Bindable"),
        ("""
        struct SettingsView: View {
            @EnvironmentObject var settings: Settings
        }
        """, "EnvironmentObject", "@Environment"),
        ("""
        class ViewModel {
            @Published var count = 0
        }
        """, "Published", "remove")
    ])
    func detectsLegacyAttribute(source: String, expectedAttribute: String, expectedSuggestion: String) throws {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .legacyObservableObject)
        #expect(issue.message.contains(expectedAttribute))
        #expect(issue.suggestion?.contains(expectedSuggestion) == true)
    }

    @Test
    func detectsObservableObjectConformance() throws {
        let source = """
        class ViewModel: ObservableObject {
            var count = 0
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .legacyObservableObject)
        #expect(issue.message.contains("ObservableObject"))
        #expect(issue.suggestion?.contains("@Observable") == true)
    }

    @Test
    func detectsObservableObjectAmongMultipleConformances() throws {
        let source = """
        class ViewModel: SomeProtocol, ObservableObject, AnotherProtocol {
            var count = 0
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("ObservableObject"))
    }

    @Test
    func observableObjectConformanceAndPublishedPropertiesEachFlagSeparately() {
        let source = """
        class ViewModel: ObservableObject {
            @Published var name = ""
            @Published var count = 0
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        // 1 for the class conformance + 2 for @Published properties
        #expect(visitor.detectedIssues.count == 3)
    }

    @Test
    func detectsFirstLegacyAttributeHasInfoSeverity() throws {
        let source = """
        struct ContentView: View {
            @StateObject var viewModel = ViewModel()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.severity == .info)
    }

    @Test
    func detectsMultipleLegacyAttributes() {
        let source = """
        class ViewModel {
            @Published var name = ""
            @Published var count = 0
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test("No issue for modern observation APIs", arguments: [
        // @State
        """
        struct ContentView: View {
            @State var count = 0
        }
        """,
        // @Environment
        """
        struct ContentView: View {
            @Environment(\\.dismiss) var dismiss
        }
        """,
        // @Bindable
        """
        struct DetailView: View {
            @Bindable var model: Model
        }
        """,
        // @Observable macro
        """
        @Observable
        class AppState {
            var count = 0
            var name = ""
        }
        """,
        // plain class with no ObservableObject conformance
        """
        class MyService: SomeProtocol {
            var count = 0
        }
        """,
        // class with no inheritance clause at all
        """
        class MyService {
            var count = 0
        }
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

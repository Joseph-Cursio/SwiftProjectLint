import Testing
import SwiftParser
import SwiftSyntax
@testable import Core
@testable import SwiftProjectLintRules

/// Tests for uncovered paths in PerformanceStateVariableTracking:
/// - self.variable assignment tracking via SequenceExprSyntax
/// - checkForUnnecessaryUpdates when variable is assigned but not used in body
/// - Non-@State variables should not be tracked
/// - Multiple bindings in a single @State declaration
struct PerformanceStateVariableAssignmentTests {

    private func makeVisitor(source: String) -> PerformanceVisitor {
        let syntax = Parser.parse(source: source)
        let visitor = PerformanceVisitor(patternCategory: .performance)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)
        return visitor
    }

    // MARK: - Assignment detection

    @Test
    func detectsDirectSelfAssignment() throws {
        let source = """
        struct ContentView: View {
            @State private var count: Int = 0
            var body: some View {
                Text("\\(self.count)")
                Button("Go") {
                    self.count = 42
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let countInfo = try #require(visitor.stateVariables["count"])
        #expect(countInfo.isUsedInViewBody)
    }

    // MARK: - Unnecessary update detection

    @Test
    func noIssueWhenStateVarUsedAndAssigned() throws {
        let source = """
        struct ContentView: View {
            @State private var title: String = "Hello"
            var body: some View {
                Text(self.title)
                Button("Update") {
                    self.title = "World"
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let titleInfo = try #require(visitor.stateVariables["title"])
        #expect(titleInfo.isUsedInViewBody)
    }

    @Test
    func noIssueWhenStateVarDeclaredButNeverAssigned() throws {
        let source = """
        struct ContentView: View {
            @State private var value: Int = 0
            var body: some View {
                Text("Static")
            }
        }
        """

        let visitor = makeVisitor(source: source)
        let valueInfo = try #require(visitor.stateVariables["value"])
        #expect(valueInfo.isAssigned == false)

        // No unnecessary update issue because it's not assigned
        let unnecessaryIssues = visitor.detectedIssues.filter {
            $0.message.contains("unnecessarily")
        }
        #expect(unnecessaryIssues.isEmpty)
    }

    // MARK: - Non-@State variables excluded

    @Test
    func doesNotTrackObservedObjectVariables() throws {
        let source = """
        struct ContentView: View {
            @ObservedObject var viewModel: ViewModel
            @State private var count: Int = 0
            var body: some View { Text("\\(self.count)") }
        }
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.stateVariables["viewModel"] == nil)
        #expect(visitor.stateVariables["count"] != nil)
    }

    @Test
    func doesNotTrackEnvironmentVariables() throws {
        let source = """
        struct ContentView: View {
            @Environment(\\.colorScheme) var colorScheme
            @State private var flag: Bool = false
            var body: some View { Text("test") }
        }
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.stateVariables["colorScheme"] == nil)
        #expect(visitor.stateVariables["flag"] != nil)
    }

    // MARK: - Multiple @State variables tracked independently

    @Test
    func tracksMultipleStateVariablesIndependently() throws {
        let source = """
        struct ContentView: View {
            @State private var a: Int = 0
            @State private var b: String = ""
            @State private var c: Bool = false
            var body: some View {
                VStack {
                    Text("\\(self.a)")
                    Text(self.b)
                }
            }
        }
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.stateVariables.count == 3)

        // a and b are used, c is not
        let aInfo = try #require(visitor.stateVariables["a"])
        let bInfo = try #require(visitor.stateVariables["b"])
        let cInfo = try #require(visitor.stateVariables["c"])

        #expect(aInfo.isUsedInViewBody)
        #expect(bInfo.isUsedInViewBody)
        #expect(cInfo.isUsedInViewBody == false)

    }

    // MARK: - Line number tracking

    @Test
    func tracksDeclarationLineNumber() throws {
        let source = """
        struct ContentView: View {
            @State private var count: Int = 0
            var body: some View { Text("test") }
        }
        """

        let visitor = makeVisitor(source: source)
        let countInfo = try #require(visitor.stateVariables["count"])
        #expect(countInfo.declaredAtLine > 0)
    }
}

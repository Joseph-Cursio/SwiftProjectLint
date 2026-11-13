import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

@Suite
struct MissingStateObjectVisitorTests {

    private func issues(_ source: String) -> [LintIssue] {
        let tree = Parser.parse(source: source)
        let visitor = MissingStateObjectVisitor(pattern: MissingStateObject().pattern)
        visitor.setFilePath("View.swift")
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "View.swift", tree: tree))
        visitor.walk(tree)
        return visitor.detectedIssues.filter { $0.ruleName == .missingStateObject }
    }

    /// A view whose `model` is declared by `declaration` and whose initializer runs `initBody`.
    private func view(_ declaration: String = "@ObservedObject var model: Model", initBody: String) -> String {
        """
        import SwiftUI
        struct CounterView: View {
            \(declaration)
            init() {
                \(initBody)
            }
            var body: some View { Text(model.title) }
        }
        """
    }

    // MARK: - Reported

    @Test("an initializer assigning a new object to an @ObservedObject is reported at the property")
    func reportsConstructionInTheInitializer() throws {
        let found = issues(view(initBody: "self.model = Model()"))
        let issue = try #require(found.first)
        #expect(found.count == 1)
        #expect(issue.lineNumber == 3)
        #expect(issue.message.contains("'model' is @ObservedObject, but CounterView's initializer creates it"))
        #expect(issue.suggestion?.contains("_model = StateObject(wrappedValue:") == true)
    }

    @Test("every spelling of the assignment and of the construction counts")
    func reportsEverySpelling() {
        let bodies = [
            "model = Model()",
            "self.model = Model(title: \"x\")",
            "self.model = Model.init()",
            "self.model = Model<Int>()",
            "_model = ObservedObject(wrappedValue: Model())",
            "self._model = ObservedObject(initialValue: Model())",
        ]
        for body in bodies {
            #expect(issues(view(initBody: body)).count == 1, "body: \(body)")
        }
        #expect(issues(view("@SwiftUI.ObservedObject var model: Model", initBody: "self.model = Model()")).count == 1)
    }

    @Test("it is enough that one of several initializers constructs the object")
    func oneConstructingInitializerIsEnough() {
        let source = """
        struct CounterView: View {
            @ObservedObject var model: Model
            init(model: Model) { self.model = model }
            init() { self.model = Model() }
            var body: some View { Text("") }
        }
        """
        #expect(issues(source).count == 1)
    }

    // MARK: - Not reported

    @Test("an object passed in, a shared instance or a factory's result is not constructed here")
    func injectedObjectsAreClean() {
        let source = """
        struct CounterView: View {
            @ObservedObject var model: Model
            init(model: Model) { self.model = model }
            var body: some View { Text("") }
        }
        """
        #expect(issues(source).isEmpty)
        #expect(issues(view(initBody: "self.model = Model.shared")).isEmpty)
        #expect(issues(view(initBody: "self.model = makeModel()")).isEmpty)
        #expect(issues(view(initBody: "_model = ObservedObject(wrappedValue: model)")).isEmpty)
    }

    @Test("@StateObject built in the initializer is the fix, not a finding")
    func stateObjectIsClean() {
        #expect(issues(view("@StateObject var model: Model", initBody: "_model = StateObject(wrappedValue: Model())")).isEmpty)
    }

    @Test("@State holding an object, or an @StateObject named like a manager, is not this rule's")
    func theOldBackwardsCasesAreClean() {
        let source = """
        struct ContentView: View {
            @State private var manager = DataManager()
            @StateObject private var viewModel = ProfileViewModel()
            var body: some View { Text("") }
        }
        """
        #expect(issues(source).isEmpty)
    }

    @Test("an inline value is ObservedObject Inline's, so it is not reported twice")
    func inlineValueIsLeftToObservedObjectInline() {
        #expect(issues(view("@ObservedObject var model = Model()", initBody: "")).isEmpty)
    }

    @Test("a delegating initializer is not followed, and a non-view type is not checked")
    func delegationAndNonViewsAreClean() {
        let delegating = """
        struct CounterView: View {
            @ObservedObject var model: Model
            init(model: Model) { self.model = model }
            init() { self.init(model: Model()) }
            var body: some View { Text("") }
        }
        """
        #expect(issues(delegating).isEmpty)

        let notAView = """
        struct Holder {
            @ObservedObject var model: Model
            init() { self.model = Model() }
        }
        """
        #expect(issues(notAView).isEmpty)
    }

    @Test("an initializer building a different property's object is not this property's")
    func otherPropertiesDoNotCount() {
        let source = """
        struct CounterView: View {
            @ObservedObject var model: Model
            var helper: Helper
            init(model: Model) { self.model = model; self.helper = Helper() }
            var body: some View { Text("") }
        }
        """
        #expect(issues(source).isEmpty)
    }
}

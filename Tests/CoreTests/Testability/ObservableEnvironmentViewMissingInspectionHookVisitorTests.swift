@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ObservableEnvironmentViewMissingInspectionHookVisitorTests {

    private func run(_ source: String) -> ObservableEnvironmentViewMissingInspectionHookVisitor {
        let pattern = SyntaxPattern(
            name: .observableEnvironmentViewMissingInspectionHook,
            visitor: ObservableEnvironmentViewMissingInspectionHookVisitor.self,
            severity: .info,
            category: .testability,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        let visitor = ObservableEnvironmentViewMissingInspectionHookVisitor(pattern: pattern)
        visitor.walk(Parser.parse(source: source))
        return visitor
    }

    // MARK: - Flagged

    @Test("View reading @Environment(Type.self) with no hook is flagged")
    func observableEnvironmentWithoutHookFlags() {
        let visitor = run("""
        struct ContentView: View {
            @Environment(VaultManager.self) private var vaultManager

            var body: some View {
                Text(vaultManager.title)
            }
        }
        """)

        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.ruleName == .observableEnvironmentViewMissingInspectionHook)
    }

    @Test("message names every offending environment type")
    func messageNamesTypes() {
        let visitor = run("""
        struct ContentView: View {
            @Environment(VaultManager.self) private var vault
            @Environment(PluginManager.self) private var plugins

            var body: some View { Text("x") }
        }
        """)

        let message = visitor.detectedIssues.first?.message ?? ""
        #expect(message.contains("VaultManager.self"))
        #expect(message.contains("PluginManager.self"))
    }

    // MARK: - Not flagged

    @Test("the keypath form degrades to a default and is not flagged")
    func keyPathEnvironmentIsClean() {
        // @Environment(\.someKey) has a default value, so it warns rather than
        // traps. Only the Type.self form is fatal.
        let visitor = run("""
        struct ContentView: View {
            @Environment(\\.dependencies) private var dependencies

            var body: some View { Text("x") }
        }
        """)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("a view that already carries the inspection relay is clean")
    func withHookIsClean() {
        let visitor = run("""
        struct ContentView: View {
            @Environment(VaultManager.self) private var vaultManager
            internal let inspection = Inspection<Self>()

            var body: some View {
                Text(vaultManager.title)
                    .onReceive(inspection.notice) { inspection.visit(self, $0) }
            }
        }
        """)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("a non-View struct is not flagged")
    func nonViewStructIsClean() {
        let visitor = run("""
        struct Holder {
            @Environment(VaultManager.self) private var vaultManager
        }
        """)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("a View with no environment reads is clean")
    func plainViewIsClean() {
        let visitor = run("""
        struct PlainView: View {
            let title: String
            var body: some View { Text(title) }
        }
        """)

        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Is anybody inspecting it?

    private func run(_ source: String, inspected: Set<String>?) -> [LintIssue] {
        let pattern = SyntaxPattern(
            name: .observableEnvironmentViewMissingInspectionHook,
            visitor: ObservableEnvironmentViewMissingInspectionHookVisitor.self,
            severity: .info,
            category: .testability,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        let visitor = ObservableEnvironmentViewMissingInspectionHookVisitor(pattern: pattern)
        visitor.knownInspectedTypeNames = inspected
        visitor.walk(Parser.parse(source: source))
        return visitor.detectedIssues
    }

    private static let subject = """
    struct SettingsView: View {
        @Environment(VaultManager.self) private var vault
        var body: some View { Text(vault.name) }
    }
    """

    @Test("A view no ViewInspector file names is not flagged")
    func uninspectedViewIsNotFlagged() {
        // The rule's own scope, which it stated and did not implement: "a view nobody inspects
        // needs no hook." All 58 corpus findings were this case.
        #expect(run(Self.subject, inspected: []).isEmpty)
    }

    @Test("A view some ViewInspector file names is flagged")
    func inspectedViewIsFlagged() {
        #expect(run(Self.subject, inspected: ["SettingsView"]).count == 1)
    }

    @Test("Another view being inspected does not implicate this one")
    func gateIsPerView() {
        #expect(run(Self.subject, inspected: ["SomeOtherView"]).isEmpty)
    }

    @Test("With no prescan the rule reports, so its own unit tests keep meaning what they say")
    func nilCatalogReports() {
        // `nil` is "nobody ran a project-wide scan", not "nobody inspects anything". A visitor
        // driven straight by a unit test has no catalog, and gating on absence would quietly
        // turn every other test in this suite into a tautology.
        #expect(run(Self.subject, inspected: nil).count == 1)
    }
}

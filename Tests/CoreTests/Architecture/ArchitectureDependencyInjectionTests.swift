import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import Core

@Suite("Missing Dependency Injection")
struct ArchitectureDependencyInjectionTests {

    // MARK: - Helpers

    private func createVisitor() -> ArchitectureVisitor {
        let pattern = SyntaxPattern(
            name: .missingDependencyInjection,
            visitor: ArchitectureVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        let visitor = ArchitectureVisitor(pattern: pattern)
        visitor.setFilePath("TestFile.swift")
        return visitor
    }

    private func detectIssues(in sourceCode: String) -> [LintIssue] {
        let visitor = createVisitor()
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        return visitor.detectedIssues
    }

    // MARK: - Inline @StateObject fires

    @Test("Inline @StateObject initialization fires missing DI")
    func stateObjectInlineInitFires() {
        let source = """
        struct MyView: View {
            @StateObject private var vm = UserViewModel()
            var body: some View { Text("") }
        }
        """
        let issues = detectIssues(in: source)
        let diIssues = issues.filter { $0.ruleName == .missingDependencyInjection }
        #expect(!diIssues.isEmpty)
    }

    // MARK: - Empty init fires

    @Test("Empty init in View-suffixed struct fires missing DI")
    func emptyInitInViewFires() {
        let source = """
        struct SettingsView: View {
            var name: String = ""
            init() {}
            var body: some View { Text(name) }
        }
        """
        let issues = detectIssues(in: source)
        let diIssues = issues.filter { $0.ruleName == .missingDependencyInjection }
        #expect(!diIssues.isEmpty)
    }

    // MARK: - @Environment suppresses empty init

    @Test("Empty init suppressed when view uses @Environment")
    func emptyInitSuppressedForEnvironment() {
        let source = """
        public struct ContentView: View {
            @Environment(AppState.self) private var appState
            public init() {}
            var body: some View { Text("") }
        }
        """
        let issues = detectIssues(in: source)
        let diIssues = issues.filter { $0.ruleName == .missingDependencyInjection }
        #expect(diIssues.isEmpty)
    }

    @Test("Empty init suppressed when view uses @EnvironmentObject")
    func emptyInitSuppressedForEnvironmentObject() {
        let source = """
        struct ProfileView: View {
            @EnvironmentObject var model: UserModel
            init() {}
            var body: some View { Text(model.name) }
        }
        """
        let issues = detectIssues(in: source)
        let diIssues = issues.filter { $0.ruleName == .missingDependencyInjection }
        #expect(diIssues.isEmpty)
    }

    // MARK: - Sibling struct bleed fix

    @Test("Non-view sibling struct's init does not inherit preceding view name")
    func siblingStructInitNotMisattributed() {
        // SkillExportView uses @Environment (no empty init to flag),
        // SkillExportDocument has init() {} but is not a View — must not fire.
        let source = """
        struct SkillExportView: View {
            @Environment(AppState.self) private var appState
            var body: some View { Text("") }
        }
        struct SkillExportDocument: FileDocument {
            init() {}
            init(configuration: ReadConfiguration) throws {}
        }
        """
        let issues = detectIssues(in: source)
        let diIssues = issues.filter { $0.ruleName == .missingDependencyInjection }
        #expect(diIssues.isEmpty)
    }

    @Test("Non-view struct init after view-suffixed struct does not fire")
    func nonViewSiblingAfterViewDoesNotFire() {
        let source = """
        struct MyView: View {
            var name: String
            init(name: String) { self.name = name }
            var body: some View { Text(name) }
        }
        struct MyModel {
            init() {}
        }
        """
        let issues = detectIssues(in: source)
        let diIssues = issues.filter { $0.ruleName == .missingDependencyInjection }
        #expect(diIssues.isEmpty)
    }
}

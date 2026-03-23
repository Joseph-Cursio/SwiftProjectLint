import Testing
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite
struct CouldBePrivateMemberVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = CouldBePrivateMember().pattern
        let visitor = CouldBePrivateMemberVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .couldBePrivateMember }
    }

    @Test func flagsMethodOnlyUsedInDeclaringFile() {
        let issues = analyze(files: [
            "MyView.swift": """
            struct MyView: View {
                func helperMethod() -> String { "hi" }
                var body: some View { Text(helperMethod()) }
            }
            """,
            "Other.swift": """
            struct Other {
                func doWork() { }
            }
            """
        ])

        let flagged = issues.map { $0.message }
        #expect(flagged.contains { $0.contains("helperMethod") })
    }

    @Test func doesNotFlagMethodUsedAcrossFiles() {
        let issues = analyze(files: [
            "Service.swift": """
            struct Service {
                func fetchData() -> [String] { [] }
            }
            """,
            "Consumer.swift": """
            struct Consumer {
                let service = Service()
                func load() { let _ = service.fetchData() }
            }
            """
        ])

        let flagged = issues.map { $0.message }
        #expect(!flagged.contains { $0.contains("fetchData") })
    }

    @Test func skipsAlreadyPrivateMembers() {
        let issues = analyze(files: [
            "MyType.swift": """
            struct MyType {
                private func secretHelper() { }
                func uniquePublicMethod() { secretHelper() }
            }
            """
        ])

        let flagged = issues.map { $0.message }
        #expect(!flagged.contains { $0.contains("secretHelper") })
        #expect(flagged.contains { $0.contains("uniquePublicMethod") })
    }

    @Test func skipsOverrides() {
        let issues = analyze(files: [
            "Child.swift": """
            class Child: Parent {
                override func viewDidLoad() { }
            }
            """
        ])

        let flagged = issues.map { $0.message }
        #expect(!flagged.contains { $0.contains("viewDidLoad") })
    }

    @Test func skipsBodyProperty() {
        let issues = analyze(files: [
            "MyView.swift": """
            struct MyView: View {
                var body: some View { Text("hi") }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test func skipsPropertyWrapperProperties() {
        let issues = analyze(files: [
            "MyView.swift": """
            struct MyView: View {
                @State var counter: Int = 0
                var body: some View { Text("hi") }
            }
            """
        ])

        let flagged = issues.map { $0.message }
        #expect(!flagged.contains { $0.contains("counter") })
    }

    @Test func flagsPropertyOnlyUsedLocally() {
        let issues = analyze(files: [
            "Helper.swift": """
            struct Helper {
                var uniqueInternalConfig: String = "default"
                func work() { let _ = uniqueInternalConfig }
            }
            """,
            "Other.swift": """
            struct Other { }
            """
        ])

        let flagged = issues.map { $0.message }
        #expect(flagged.contains { $0.contains("uniqueInternalConfig") })
    }
}

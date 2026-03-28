import Testing
import SwiftSyntax
import SwiftParser
@testable import Core

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
        #expect(flagged.contains { $0.contains("fetchData") } == false)

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
        #expect(flagged.contains { $0.contains("secretHelper") } == false)

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
        #expect(flagged.contains { $0.contains("viewDidLoad") } == false)

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
        #expect(flagged.contains { $0.contains("counter") } == false)

    }

    // MARK: - Enum and Actor Type Tracking

    @Test func flagsMemberInEnum() {
        let issues = analyze(files: [
            "Status.swift": """
            enum Status {
                case active
                func label() -> String { "active" }
            }
            """,
            "Other.swift": """
            struct Other { }
            """
        ])

        let flagged = issues.map(\.message)
        #expect(flagged.contains { $0.contains("label") })
    }

    @Test func flagsMemberInActor() {
        let issues = analyze(files: [
            "Store.swift": """
            actor Store {
                func reset() { }
            }
            """,
            "Other.swift": """
            struct Other { }
            """
        ])

        let flagged = issues.map(\.message)
        #expect(flagged.contains { $0.contains("reset") })
    }

    // MARK: - Closure and Accessor Nesting

    @Test func doesNotFlagLocalFunctionInsideClosure() {
        let issues = analyze(files: [
            "Widget.swift": """
            struct Widget {
                func render() {
                    let block = {
                        func localHelper() { }
                        localHelper()
                    }
                    block()
                }
            }
            """,
            "Other.swift": """
            struct Other { }
            """
        ])

        let flagged = issues.map(\.message)
        #expect(flagged.contains { $0.contains("localHelper") } == false)
    }

    // MARK: - Skip @objc Members

    @Test func skipsObjcMember() {
        let issues = analyze(files: [
            "Handler.swift": """
            class Handler {
                @objc func tapped() { }
            }
            """,
            "Other.swift": """
            struct Other { }
            """
        ])

        let flagged = issues.map(\.message)
        #expect(flagged.contains { $0.contains("tapped") } == false)
    }

    // MARK: - Skip Operators

    @Test func skipsOperatorMethods() {
        let issues = analyze(files: [
            "Token.swift": """
            struct Token {
                static func ==(lhs: Token, rhs: Token) -> Bool { true }
                static func <(lhs: Token, rhs: Token) -> Bool { true }
            }
            """,
            "Other.swift": """
            struct Other { }
            """
        ])

        let flagged = issues.map(\.message)
        #expect(flagged.contains { $0.contains("==") } == false)
        #expect(flagged.contains { $0.contains("<") } == false)
    }

    // MARK: - Skip Members Inside Private Types

    @Test func skipsMethodInsidePrivateStruct() {
        let issues = analyze(files: [
            "Internal.swift": """
            private struct Internal {
                func helper() { }
            }
            """,
            "Other.swift": """
            struct Other { }
            """
        ])

        let flagged = issues.map(\.message)
        #expect(flagged.contains { $0.contains("helper") } == false)
    }

    // MARK: - Struct Stored Properties Without Defaults

    @Test func skipsStructStoredPropertyWithoutDefault() {
        let issues = analyze(files: [
            "Config.swift": """
            struct Config {
                var name: String
                var count: Int
            }
            """,
            "Other.swift": """
            struct Other { }
            """
        ])

        let flagged = issues.map(\.message)
        #expect(flagged.contains { $0.contains("name") } == false)
        #expect(flagged.contains { $0.contains("count") } == false)
    }

    // MARK: - Existing tests

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

@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct MissingEquatableOnStateTypeVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = MissingEquatableOnStateType().pattern
        let visitor = MissingEquatableOnStateTypeVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .missingEquatableOnStateType }
    }

    @Test
    func flagsNonEquatableStateType() {
        let issues = analyze(files: [
            "Source.swift": """
            struct Settings {
                var volume: Int
            }
            struct ContentView {
                @State private var settings: Settings
            }
            """
        ])
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'Settings'") == true)
    }

    @Test
    func ignoresEquatableStateType() {
        let issues = analyze(files: [
            "Source.swift": """
            struct Settings: Equatable {
                var volume: Int
            }
            struct ContentView {
                @State private var settings: Settings
            }
            """
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func ignoresHashableStateType() {
        let issues = analyze(files: [
            "Source.swift": """
            struct Settings: Hashable {
                var volume: Int
            }
            struct ContentView {
                @Binding var settings: Settings
            }
            """
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func seesEquatableAddedViaExtensionInAnotherFile() {
        let issues = analyze(files: [
            "Model.swift": """
            struct Settings {
                var volume: Int
            }
            """,
            "Conformance.swift": """
            extension Settings: Equatable {}
            """,
            "View.swift": """
            struct ContentView {
                @State var settings: Settings
            }
            """
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func flagsAcrossFilesWhenConformanceIsAbsent() {
        let issues = analyze(files: [
            "Model.swift": """
            struct Settings {
                var volume: Int
            }
            """,
            "View.swift": """
            struct ContentView {
                @State var settings: Settings
            }
            """
        ])
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'Settings'") == true)
    }

    @Test
    func flagsPublishedAndEnumStateTypes() {
        let issues = analyze(files: [
            "Source.swift": """
            enum LoadState {
                case idle
                case loading
            }
            class ViewModel {
                @Published var state: LoadState = .idle
            }
            """
        ])
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'LoadState'") == true)
    }

    @Test
    func unwrapsOptionalAndArrayStateTypes() {
        let issues = analyze(files: [
            "Source.swift": """
            struct Item {
                var id: Int
            }
            struct ListView {
                @State var selected: Item?
                @State var items: [Item]
            }
            """
        ])
        // Both bindings reference the same non-Equatable `Item`; one issue at its decl.
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'Item'") == true)
    }

    @Test
    func ignoresExternalOrPrimitiveStateTypes() {
        let issues = analyze(files: [
            "Source.swift": """
            struct ContentView {
                @State var count: Int
                @State var name: String
                @State var external: SomeThirdPartyType
            }
            """
        ])
        // Int/String are Equatable stdlib types; SomeThirdPartyType isn't declared
        // in the project, so it can't be judged. No flags.
        #expect(issues.isEmpty)
    }

    @Test
    func ignoresReferenceWrappers() {
        let issues = analyze(files: [
            "Source.swift": """
            struct Model {
                var x: Int
            }
            struct ContentView {
                @StateObject var model: Model
                @ObservedObject var other: Model
            }
            """
        ])
        // @StateObject / @ObservedObject wrap reference types; not in scope.
        #expect(issues.isEmpty)
    }

    @Test
    func emitsOneIssuePerTypeNotPerUsage() {
        let issues = analyze(files: [
            "A.swift": """
            struct Shared {
                var v: Int
            }
            struct ViewA {
                @State var shared: Shared
            }
            """,
            "B.swift": """
            struct ViewB {
                @Binding var shared: Shared
            }
            """
        ])
        #expect(issues.count == 1)
    }
}

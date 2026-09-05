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
        // The enum carries a payload. It used to be `case idle, loading`, which is payload-free
        // and therefore `Equatable` by synthesis — so this test asserted a false positive and
        // was the reason the bug had a test defending it. The `@Published` coverage it was
        // written for is unchanged; only the premise is.
        let issues = analyze(files: [
            "Source.swift": """
            enum LoadState {
                case idle
                case failed(Error)
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

    // MARK: - Conformances the compiler supplies

    // A payload-free enum is `Equatable` and `Hashable` without saying so. Telling a reader to
    // add a conformance the language already gave them is advice they cannot act on, and it was
    // the commonest shape this rule fired on: five of six findings in SwiftLintRuleStudioTeam,
    // every one of them a state enum.
    //
    // `EquatableConformanceCollector` has always known this — the candidate gate was correct
    // while the nag was not, so the two disagreed about the same language guarantee.

    @Test
    func ignoresPayloadFreeEnumWithNoDeclaredConformance() {
        let issues = analyze(files: [
            "Source.swift": """
            enum AppSection { case fleet, standards, compare }
            struct RootView {
                @State private var section: AppSection
            }
            """
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func ignoresRawValueEnumInState() {
        // A raw-value enum cannot carry associated values, so the synthesis always applies.
        let issues = analyze(files: [
            "Source.swift": """
            enum SortOrder: String, CaseIterable, Identifiable {
                case health = "Health"
                case name = "Name"
                var id: String { rawValue }
            }
            struct FleetView {
                @State private var order: SortOrder
            }
            """
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func flagsEnumWithAssociatedValues() {
        // The control that keeps the fix honest. An enum WITH a payload is `Equatable` only when
        // it declares it — the compiler checks every payload is itself `Equatable` — so this one
        // must still be reported.
        let issues = analyze(files: [
            "Source.swift": """
            enum LoadState { case idle, failed(Error) }
            struct StatusView {
                @State private var state: LoadState
            }
            """
        ])
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'LoadState'") == true)
    }

    @Test
    func stillFlagsAStructInState() {
        // The other control: a struct gets no free conformance, and this is the shape the rule
        // exists for. In the repo that prompted the fix it was the single true positive.
        let issues = analyze(files: [
            "Source.swift": """
            struct AnnotationTarget: Identifiable { let id: String }
            struct DetailView {
                @State private var target: AnnotationTarget
            }
            """
        ])
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'AnnotationTarget'") == true)
    }

}

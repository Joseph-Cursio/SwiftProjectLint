@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

private func analyze(_ source: String, filePath: String = "ContentView.swift") -> [LintIssue] {
    let visitor = UnreachableEffectClosureVisitor(patternCategory: .testability)
    let syntax = Parser.parse(source: source)
    visitor.setSourceLocationConverter(
        SourceLocationConverter(fileName: filePath, tree: syntax)
    )
    visitor.setFilePath(filePath)
    visitor.walk(syntax)
    return visitor.detectedIssues.filter { $0.ruleName == .unreachableEffectClosure }
}

/// Condition 4: the effect has to have somewhere to be observed from.
///
/// The rule's description makes a testability claim — *"no test can reach its effect … naming it
/// gives the effect one"* — and for a write to the enclosing view's own `@State` that claim is
/// false. `Tests/AppTests/StateSeamHarnessTests.swift` is the measurement: calling the extracted
/// method on an uninstalled view leaves the property unchanged, reading it back through the
/// rendered body shows the same, and firing the button through ViewInspector reaches it no better.
/// The seam a test uses is the button, and the button exists in both forms.
///
/// The same harness shows where the promise *does* hold, which is what these tests pin: `@Binding`
/// writes into storage a test supplies, `@AppStorage` writes straight through to the defaults
/// store, and a member write lands on an object that outlives the view.
@Suite("A write to the view's own @State has no seam to gain")
struct UnreachableEffectClosureViewStateTests {

    // MARK: - Gated

    @Test("a Button writing only the view's own @State is not reported")
    func stateOnlyButtonIsNotReported() {
        let issues = analyze("""
        struct LoginView: View {
            @State private var showingConfig = false

            var body: some View {
                Button("Configure") {
                    showingConfig = true
                }
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("several @State writes in one body are still gated")
    func multipleStateWritesAreGated() {
        // The corpus shape: an alert's OK button clearing two flags at once.
        let issues = analyze("""
        struct ContentView: View {
            @State private var errorMessage: String?
            @State private var showError = false

            var body: some View {
                Button("OK") {
                    errorMessage = nil
                    showError = false
                }
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("toggle and compound assignment on @State are gated too")
    func toggleAndCompoundAssignmentAreGated() {
        let issues = analyze("""
        struct ContentView: View {
            @State private var isExpanded = false
            @State private var step = 0

            var body: some View {
                Button("More") {
                    isExpanded.toggle()
                    step += 1
                }
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("@FocusState is gated on the same measurement")
    func focusStateIsGated() {
        let issues = analyze("""
        struct ContentView: View {
            @FocusState private var focus: Field?

            var body: some View {
                Button("Name") {
                    focus = .name
                }
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    // MARK: - Still reported, because the seam is real

    @Test("a @Binding write is reported — the parent owns the storage")
    func bindingWriteIsReported() throws {
        // A test supplies its own `Binding(get:set:)` and reads the write back, so the extracted
        // method genuinely becomes assertable. Fifteen of the corpus write targets are these.
        let issues = analyze("""
        struct ConfigRow: View {
            @Binding var serverURL: String

            var body: some View {
                Button("Local Development") {
                    serverURL = "http://localhost:8080"
                }
            }
        }
        """)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("Button"))
    }

    @Test("an @AppStorage write is reported — it lands in the defaults store")
    func appStorageWriteIsReported() {
        let issues = analyze("""
        struct SizeCommands: View {
            @AppStorage("textSizeStep") private var textSizeStep = 0

            var body: some View {
                Button("Larger Text") {
                    textSizeStep = min(textSizeStep + 1, 4)
                }
            }
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("a member write is reported — the object outlives the view")
    func memberWriteIsReported() {
        let issues = analyze("""
        struct SearchBar: View {
            @Bindable var viewModel: SearchViewModel

            var body: some View {
                Button("Clear") {
                    viewModel.searchQuery = ""
                    viewModel.searchResults = []
                }
            }
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("one non-@State write anywhere keeps the whole finding")
    func mixedBodyIsReported() {
        // The gate's claim is about the *only* thing the body does, so a body that clears a flag
        // and also touches a model is not gated. Under-gating is the safe direction here.
        let issues = analyze("""
        struct ContentView: View {
            @State private var showingSheet = false
            let viewModel: ViewModel

            var body: some View {
                Button("Apply") {
                    showingSheet = false
                    viewModel.apply()
                    viewModel.dirty = true
                }
            }
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("a body of nothing but mutating calls is not reported, and never was")
    func mutatingCallsAloneAreNotReported() {
        // Not this gate. `PurityInferrer.mutatesCapturedState` detects *assignments* only, so a
        // closure whose whole body is `items.append(x)` never satisfied condition 2 and has never
        // been reported by this rule. Recorded here rather than left as a surprise: closing it
        // would raise the count, and it is filed rather than done quietly.
        let issues = analyze("""
        struct ContentView: View {
            @State private var items: [Int] = []

            var body: some View {
                Button("Add") {
                    items.append(1)
                    items.append(2)
                }
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("a mutating call beside an assignment disqualifies the gate")
    func mutatingCallBesideAnAssignmentIsReported() {
        // Where the disqualifier is reachable. Whether `items` is a value the view owns or an
        // object it merely references cannot be told from syntax, so the finding is kept.
        let issues = analyze("""
        struct ContentView: View {
            @State private var isAdding = false
            @State private var items: [Int] = []

            var body: some View {
                Button("Add") {
                    isAdding = false
                    items.append(1)
                }
            }
        }
        """)
        #expect(issues.count == 1)
    }

    // MARK: - Per type, not per file

    @Test("the same name is @State in one view and @Binding in another")
    func stateNamesAreKeyedByType() throws {
        // Two views in one file routinely use the same property name for different storage. A
        // file-wide set would let the first view's `@State private var text` gate the second
        // view's `@Binding var text`, which the harness says is a real seam.
        let issues = analyze("""
        struct OwnerView: View {
            @State private var text = ""

            var body: some View {
                Button("Clear") { text = "" }
            }
        }

        struct ChildView: View {
            @Binding var text: String

            var body: some View {
                Button("Reset") { text = "" }
            }
        }
        """)
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.symbol == "body")
    }
}

@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ArchitectureComputedPropertyViewTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = ComputedPropertyViewVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .computedPropertyView }
    }

    // MARK: - Positive: flags computed properties returning some View
    //
    // Each fixture below carries a stored input the flagged property does not read. That is not
    // decoration: the rule reports a property only when extracting it would give the child a
    // narrower input surface than its parent, so a view with no inputs at all has nothing to
    // narrow and is deliberately silent. The gate itself is specified in its own suite at the
    // bottom of this file.

    @Test func testFlagsComputedPropertyReturningView() throws {
        let source = """
        struct ContentView: View {
            let title: String
            var header: some View {
                Text("Title")
            }
            var body: some View {
                VStack { header; Text(title) }
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.message.contains("header"))
        #expect(issue.severity == .warning)
    }

    @Test func testFlagsMultipleComputedProperties() {
        let source = """
        struct MyView: View {
            let title: String
            var header: some View { Text("H") }
            var footer: some View { Text("F") }
            var body: some View {
                VStack { header; footer; Text(title) }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
        let names = issues.compactMap(\.message)
        #expect(names.contains { $0.contains("header") })
        #expect(names.contains { $0.contains("footer") })
    }

    @Test func testViewBuilderPropertyFlaggedAsInfo() throws {
        let source = """
        struct MyView: View {
            let title: String
            @ViewBuilder
            var content: some View {
                Text("Hello")
            }
            var body: some View { VStack { content; Text(title) } }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("@ViewBuilder"))
    }

    @Test func testDetectsViewViaBodyHeuristic() {
        let source = """
        struct CustomView {
            let title: String
            var body: some View {
                VStack { sidebar; Text(title) }
            }
            var sidebar: some View {
                Text("Side")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("sidebar") == true)
    }

    // MARK: - Negative: should NOT flag

    @Test func testBodyPropertyNotFlagged() {
        let source = """
        struct ContentView: View {
            var body: some View {
                Text("Hello")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNonViewTypeNotFlagged() {
        let source = """
        struct Utility {
            var helper: some View {
                Text("Not in a View type")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testStoredPropertyNotFlagged() {
        let source = """
        struct MyView: View {
            var title: String = "Hello"
            var body: some View {
                Text(title)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testClassConformingToView() {
        let source = """
        class MyViewController: View {
            let title: String
            var header: some View {
                Text("Title")
            }
            var body: some View {
                VStack { header; Text(title) }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("header") == true)
    }

    @Test func testComputedPropertyReturningNonView() {
        let source = """
        struct MyView: View {
            var title: String { "Hello" }
            var body: some View {
                Text(title)
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

/// The gate that decides whether extracting a `some View` property would buy anything.
///
/// The rule's premise is real — an inlined computed property has no node in the view graph and
/// re-evaluates whenever its parent does, while a child `View` struct can skip its `body` when its
/// inputs compare equal. What the rule used to omit is that the child only skips when its inputs
/// are *narrower*. A child taking everything its parent takes re-renders in lockstep: same work,
/// one more type.
///
/// Measured on this project's own app before the gate: seven of eighteen findings had exactly that
/// shape.
@Suite("Extracting a view property must narrow its inputs")
struct ComputedPropertyViewSubsetGateTests {

    private func filteredIssues(_ source: String) -> [LintIssue] {
        let visitor = ComputedPropertyViewVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        )
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.computedPropertyView }
    }

    @Test("a property reading fewer inputs than the view is flagged")
    func narrowerPropertyIsFlagged() {
        // `summary` ignores `isExpanded`, so a child taking only `issue` skips the re-render that
        // toggling the disclosure causes. That is the whole benefit, and here it is available.
        let issues = filteredIssues("""
        struct Row: View {
            let issue: String
            @State private var isExpanded = false
            var summary: some View { Text(issue) }
            var body: some View {
                VStack { summary; Toggle("", isOn: $isExpanded) }
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("summary") == true)
    }

    @Test("a property reading every input is not flagged")
    func propertyUsingEveryInputIsNotFlagged() {
        // Nothing to narrow: `everything` re-renders exactly when the view does.
        #expect(filteredIssues("""
        struct Row: View {
            let issue: String
            @State private var isExpanded = false
            var everything: some View {
                VStack { Text(issue); Text(isExpanded ? "open" : "shut") }
            }
            var body: some View { everything }
        }
        """).isEmpty)
    }

    @Test("a dependency reached through another property still counts")
    func transitiveDependencyIsNotFlagged() {
        // `wrapper` reads no input directly and would look input-free to a shallow check. It calls
        // `toggle`, which reads `isExpanded`, so extracting it narrows nothing. Without following
        // this edge every wrapper property in a view fires.
        #expect(filteredIssues("""
        struct Row: View {
            let issue: String
            @State private var isExpanded = false
            var toggle: some View { Toggle(issue, isOn: $isExpanded) }
            var wrapper: some View { HStack { toggle } }
            var body: some View { wrapper }
        }
        """).isEmpty)
    }

    @Test("a view with no inputs has nothing to narrow")
    func viewWithoutInputsIsNotFlagged() {
        // A view whose value carries no inputs already compares equal to itself, so SwiftUI can
        // skip it without help. Extracting a constant subview out of a constant view moves work
        // rather than saving it.
        #expect(filteredIssues("""
        struct Banner: View {
            var header: some View { Text("Title") }
            var body: some View { header }
        }
        """).isEmpty)
    }

    @Test("a static constant is not an input")
    func staticConstantIsNotAnInput() {
        // `spacing` cannot change, so it is not something the view re-renders on. Counting it as an
        // input would make `header` look like a strict subset of {spacing, title} and fire on a
        // view that has only one real input.
        let issues = filteredIssues("""
        struct Banner: View {
            static let spacing: Double = 8
            let title: String
            var header: some View { Text("Title").padding(Self.spacing) }
            var body: some View { VStack { header; Text(title) } }
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("the message says why extraction would help")
    func messageExplainsTheBenefit() {
        // The old message asserted a benefit unconditionally. Now that the finding is conditional,
        // the message has to carry the condition, or a reader cannot tell it from the old one.
        let issues = filteredIssues("""
        struct Row: View {
            let issue: String
            @State private var isExpanded = false
            var summary: some View { Text(issue) }
            var body: some View { VStack { summary; Toggle("", isOn: $isExpanded) } }
        }
        """)
        #expect(issues.first?.message.contains("fewer of this view's inputs") == true)
    }
}

/// A property that supplies a dialog's buttons is not extractable into a `View` struct.
///
/// `confirmationDialog(actions:)`, `alert(actions:)`, `Menu(content:)` and `contextMenu` read the
/// buttons out of the builder they are handed. Wrapping them in a `View` interposes a container
/// those APIs are not specified to accept, so following the rule's advice there changes what the
/// app does rather than only how it redraws — the one place this rule could break something.
///
/// Found on MacCloud_client_iOS: `FileListView` had three such properties and the rule reported
/// all three. Lowering them to `info` for carrying `@ViewBuilder` is not the same as declining.
@Suite("A dialog's buttons are not an extractable subview")
struct ComputedPropertyViewButtonCollectionTests {

    private func filteredIssues(_ source: String) -> [LintIssue] {
        let visitor = ComputedPropertyViewVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        )
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.computedPropertyView }
    }

    @Test("a confirmation dialog's actions are not reported")
    func confirmationDialogActionsAreNotReported() {
        #expect(filteredIssues("""
        struct Row: View {
            let title: String
            @State private var showing = false
            @ViewBuilder
            private var fileActions: some View {
                Button("Delete", role: .destructive) { }
                Button("Cancel", role: .cancel) { }
            }
            var body: some View {
                Text(title)
                    .confirmationDialog("Pick", isPresented: $showing) { fileActions }
            }
        }
        """).isEmpty)
    }

    @Test("an alert's actions are not reported")
    func alertActionsAreNotReported() {
        #expect(filteredIssues("""
        struct Row: View {
            let title: String
            @State private var showing = false
            @ViewBuilder
            private var deleteActions: some View {
                Button("Delete", role: .destructive) { }
            }
            var body: some View {
                Text(title)
                    .alert("Sure?", isPresented: $showing) { deleteActions }
            }
        }
        """).isEmpty)
    }

    @Test("a menu's content is not reported")
    func menuContentIsNotReported() {
        #expect(filteredIssues("""
        struct Row: View {
            let title: String
            @State private var showing = false
            @ViewBuilder
            private var moreMenuItems: some View {
                Button("Upload") { }
                Button("New Folder") { }
            }
            var body: some View {
                HStack {
                    Text(title)
                    Menu(content: { moreMenuItems }, label: { Text("More") })
                    Toggle("", isOn: $showing)
                }
            }
        }
        """).isEmpty)
    }

    // MARK: - The controls

    @Test("the same property in ordinary content is still reported")
    func ordinaryContentIsStillReported() {
        // The control the gate needs, and the reason it keys on the *consumer* rather than on
        // `@ViewBuilder`: an identical property placed in a `VStack` has no dialog to break.
        let issues = filteredIssues("""
        struct Row: View {
            let title: String
            @State private var showing = false
            @ViewBuilder
            private var buttons: some View {
                Button("Delete", role: .destructive) { }
            }
            var body: some View {
                VStack {
                    buttons
                    Text(title)
                    Toggle("", isOn: $showing)
                }
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("buttons") == true)
    }

    @Test("a sibling not used by the dialog is still reported")
    func siblingOutsideTheDialogIsStillReported() {
        // The gate must spare the dialog's own builder without silencing the whole type.
        let issues = filteredIssues("""
        struct Row: View {
            let title: String
            @State private var showing = false
            @ViewBuilder
            private var fileActions: some View {
                Button("Delete", role: .destructive) { }
            }
            private var header: some View { Text("Files") }
            var body: some View {
                VStack {
                    header
                    Text(title)
                    Toggle("", isOn: $showing)
                }
                .confirmationDialog("Pick", isPresented: $showing) { fileActions }
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("header") == true)
    }

    @Test("the receiver of a dialog modifier is not swept up")
    func modifierReceiverIsNotSweptUp() {
        // `.confirmationDialog` is a member call whose *called expression* holds the entire view it
        // is applied to. Searching that instead of the arguments would collect every name in
        // `body`, and the rule would go silent on any file containing one dialog.
        let issues = filteredIssues("""
        struct Row: View {
            let title: String
            @State private var showing = false
            private var summary: some View { Text(title) }
            @ViewBuilder
            private var actions: some View { Button("OK") { } }
            var body: some View {
                VStack {
                    summary
                    Toggle("", isOn: $showing)
                }
                .confirmationDialog("Pick", isPresented: $showing) { actions }
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("summary") == true)
    }
}

/// A child that must be handed a `Binding` or a capturing closure cannot be skipped, so extracting
/// it buys nothing.
///
/// **Measured rather than assumed.** A harness counting `body` evaluations while changing state no
/// child reads (iOS 26.5, three changes): a child with no inputs, a value input, or a
/// *non-capturing* closure re-rendered **0** times; a child holding a `@Binding` or a *capturing*
/// closure re-rendered **3** — once per change, exactly as often as the inlined property it
/// replaced.
///
/// The distinction is capture, not closures. `action: { }` compiles to one static function and
/// compares equal; `action: { showingSheet = true }` allocates a fresh context on every parent body
/// run. The first version of that harness used the non-capturing form and reported the opposite
/// conclusion, which is why the shape matters more than the type.
@Suite("A child needing a binding or a capturing closure is not worth extracting")
struct ComputedPropertyViewCaptureTests {

    private func filteredIssues(_ source: String) -> [LintIssue] {
        let visitor = ComputedPropertyViewVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        )
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.computedPropertyView }
    }

    @Test("a property writing through a projected value is not reported")
    func projectedValueIsNotReported() {
        // `$draft` would have to cross the boundary as a `@Binding`, which re-renders every time.
        #expect(filteredIssues("""
        struct Form: View {
            let title: String
            @State private var draft = ""
            @State private var other = false
            private var field: some View { TextField("", text: $draft) }
            var body: some View {
                VStack { field; Text(title); Toggle("", isOn: $other) }
            }
        }
        """).isEmpty)
    }

    @Test("a property assigning to state is not reported")
    func assignmentIsNotReported() {
        // The assignment has to become a closure the parent supplies, and it captures.
        #expect(filteredIssues("""
        struct Form: View {
            let title: String
            @State private var showing = false
            @State private var other = false
            private var opener: some View {
                Button("Configure") { showing = true }
            }
            var body: some View {
                VStack { opener; Text(title); Toggle("", isOn: $other) }
            }
        }
        """).isEmpty)
    }

    @Test("a property calling one of the view's own methods is not reported")
    func instanceMethodCallIsNotReported() {
        // `submit` captures the view. This is the `Button(action: performLogin)` shape.
        #expect(filteredIssues("""
        struct Form: View {
            let title: String
            @State private var other = false
            private var submitButton: some View {
                Button("Submit", action: submit)
            }
            private func submit() { }
            var body: some View {
                VStack { submitButton; Text(title); Toggle("", isOn: $other) }
            }
        }
        """).isEmpty)
    }

    @Test("a property composing one that needs a binding is not reported either")
    func captureIsFollowedTransitively() {
        // `form` reads nothing itself, but extracting it means passing `$draft` down through it.
        #expect(filteredIssues("""
        struct Screen: View {
            let title: String
            @State private var draft = ""
            @State private var other = false
            private var field: some View { TextField("", text: $draft) }
            private var form: some View { VStack { field } }
            var body: some View {
                VStack { form; Text(title); Toggle("", isOn: $other) }
            }
        }
        """).isEmpty)
    }

    // MARK: - The controls

    @Test("a value-only property is still reported")
    func valueOnlyPropertyIsStillReported() {
        // The measured win: a child taking a `String` compares equal and is skipped. If this stops
        // firing the rule has nothing left to say.
        let issues = filteredIssues("""
        struct Row: View {
            let title: String
            @State private var other = false
            private var heading: some View { Text(title).font(.headline) }
            var body: some View {
                VStack { heading; Toggle("", isOn: $other) }
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("heading") == true)
    }

    @Test("a property with no inputs at all is still reported")
    func inputFreePropertyIsStillReported() {
        let issues = filteredIssues("""
        struct Row: View {
            let title: String
            @State private var other = false
            private var logo: some View { Image(systemName: "cloud") }
            var body: some View {
                VStack { logo; Text(title); Toggle("", isOn: $other) }
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("logo") == true)
    }

    @Test("a static method call does not count as capture")
    func staticMethodIsNotCapture() {
        // Only instance methods capture the view. A static helper is reachable from anywhere.
        let issues = filteredIssues("""
        struct Row: View {
            let title: String
            @State private var other = false
            private var heading: some View { Text(Self.format(title)) }
            private static func format(_ text: String) -> String { text }
            var body: some View {
                VStack { heading; Toggle("", isOn: $other) }
            }
        }
        """)
        #expect(issues.count == 1)
    }
}

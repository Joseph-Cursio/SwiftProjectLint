@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

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

    /// `isExpanded.toggle()` is the same mutation as `isExpanded = true`, and only one of the two
    /// was gated.
    ///
    /// The `toggle` branch has existed since this gate was written and had **never fired**.
    /// `referencedNames(in:)` inspected a node's children and not the node itself, so handing it
    /// the bare `isExpanded` base returned the empty set. Every other caller passes a container,
    /// for which a root that is itself a reference is impossible — so the one caller that passed a
    /// bare reference was the one place the gap could show, and nothing pointed at it.
    ///
    /// Found by hand-classifying `LintIssueRow`, the file this gate was originally calibrated
    /// against, and noticing that its expand button was still reported.
    @Test("a property mutating state through toggle() is not worth extracting")
    func toggleCountsAsCapture() {
        #expect(filteredIssues("""
        struct Row: View {
            let issue: String
            @State private var isExpanded = false
            private var expandToggle: some View {
                Button { isExpanded.toggle() } label: { Text("x") }
            }
            var body: some View { VStack { expandToggle; Text(issue) } }
        }
        """).isEmpty)
    }

    @Test("the shape survives being wrapped in withAnimation")
    func toggleInsideWithAnimationCountsAsCapture() {
        // `LintIssueRow`'s actual spelling, which is why the miss reached the corpus.
        #expect(filteredIssues("""
        struct Row: View {
            let issue: String
            @State private var isExpanded = false
            private var expandToggle: some View {
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: { Text("x") }
            }
            var body: some View { VStack { expandToggle; Text(issue) } }
        }
        """).isEmpty)
    }

    /// The non-vacuity guard. `toggle()` on something that is *not* one of the type's stored
    /// inputs is not capture, and the property stays reported.
    @Test("toggle on a local is not capture")
    func toggleOnALocalIsStillReported() {
        let issues = filteredIssues("""
        struct Row: View {
            let issue: String
            @State private var isExpanded = false
            private var badge: some View {
                let flag = Flag()
                flag.toggle()
                return Text(issue)
            }
            var body: some View { VStack { badge; Text(isExpanded ? "a" : "b") } }
        }
        """)
        #expect(issues.count == 1)
    }

    /// A callback the view is *handed* crosses the boundary exactly as one it *makes*.
    ///
    /// The gate caught a closure a property creates and missed one it forwards, which is the same
    /// closure arriving by a different route. `Button("ok", action: onConfirm)` puts `onConfirm`
    /// into the child, and whether that child can ever compare equal is decided by the call site
    /// that supplied it — invisible from here, and in every corpus instance it captures.
    ///
    /// Measured before the gate was written: 13 findings across six repositories, 0 newly
    /// reported. Two of the thirteen had already been declined by hand in the code they name,
    /// which is the calibration — the gate silences the properties a reader had independently
    /// judged not worth extracting.
    @Test("a property forwarding a closure input is not worth extracting")
    func forwardedClosureCountsAsCapture() {
        #expect(filteredIssues("""
        struct Sheet: View {
            let title: String
            let onConfirm: () -> Void
            private var footer: some View { Button("ok", action: onConfirm) }
            var body: some View { VStack { footer; Text(title) } }
        }
        """).isEmpty)
    }

    @Test("an optional closure input counts too")
    func optionalClosureInputCountsAsCapture() {
        // `(() -> Void)?` parses as an optional wrapping a *parenthesised* function type, which is
        // a one-element tuple. The corpus writes callbacks this way as often as the plain form.
        #expect(filteredIssues("""
        struct Row: View {
            let title: String
            var onTap: (() -> Void)?
            private var button: some View { Button("x") { onTap?() } }
            var body: some View { VStack { button; Text(title) } }
        }
        """).isEmpty)
    }

    @Test("an attributed closure input counts too")
    func attributedClosureInputCountsAsCapture() {
        #expect(filteredIssues("""
        struct Row: View {
            let title: String
            let onApply: @Sendable (Int) -> Void
            private var button: some View { Button("a") { onApply(1) } }
            var body: some View { VStack { button; Text(title) } }
        }
        """).isEmpty)
    }

    /// The non-vacuity guard. A stored property that is *not* a closure does not gate, or this
    /// would silence every property that reads any input.
    @Test("a value input is still reported")
    func valueInputIsStillReported() {
        let issues = filteredIssues("""
        struct Row: View {
            let title: String
            let onConfirm: () -> Void
            private var heading: some View { Text(title) }
            var body: some View { VStack { heading; Button("ok", action: onConfirm) } }
        }
        """)
        #expect(issues.count == 1)
    }
}

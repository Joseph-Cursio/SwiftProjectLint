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

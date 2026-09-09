@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// A type split across files is a type this rule only partly knows.
///
/// The gate reports a property whose transitive dependency on the enclosing view's stored inputs is
/// a **strict subset** of them. That premise is that the dependency set is known — and for a type
/// whose members live in `Foo.swift` and `Foo+Sections.swift` it is not. The failure is silent and
/// runs one way: an unseen sibling contributes no dependencies, so a property forwarding to one
/// reads as depending on *nothing*, which is the strongest possible pass. **The rule was at its
/// most confident exactly where it knew least.**
///
/// Measured on SwiftLintRuleStudio: 7 of the rule's 20 findings sat in types split across files,
/// and the pre-scan catalog removed 5 of them (the other 2 reach no unseen member and still fire).
/// `RuleAuditView.auditResultsView` is the clearest — it composes two extension properties that
/// between them read six stored properties and call four instance methods, so with the whole type
/// in view the capture gate declines it outright.
@Suite("A type split across files is only partly known")
struct ComputedPropertyViewSplitTypeTests {

    private func filteredIssues(
        _ source: String,
        extensionMembers: ExtensionMemberCatalog = .empty
    ) -> [LintIssue] {
        let visitor = ComputedPropertyViewVisitor(patternCategory: .architecture)
        visitor.knownExtensionMembers = extensionMembers
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "TestFile.swift", tree: syntax)
        )
        visitor.setFilePath("TestFile.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.computedPropertyView }
    }

    private let forwardingToASibling = """
    struct Screen: View {
        let title: String
        @State private var isBusy = false
        @State private var showingSheet = false
        private var results: some View {
            VStack {
                summaryCards
                list
            }
        }
        var body: some View {
            VStack {
                results
                Text(title)
                Toggle("", isOn: $showingSheet)
                if isBusy { ProgressView() }
            }
        }
    }
    """

    @Test("a property forwarding to a member in another file is not reported")
    func siblingInAnotherFileIsNotReported() {
        // `summaryCards` and `list` are declared in `Screen+Sections.swift`. Without the catalog
        // they contribute nothing, so `results` reads as depending on no input at all.
        let catalog = ExtensionMemberCatalog(membersByType: ["Screen": ["summaryCards", "list"]])
        #expect(filteredIssues(forwardingToASibling, extensionMembers: catalog).isEmpty)
    }

    @Test("without the catalog the same property fires, which is the defect")
    func withoutTheCatalogItFires() {
        // The control, and the reason the catalog exists. This is what every run of this rule did
        // before the pre-scan: an unknown dependency set read as an empty one.
        let issues = filteredIssues(forwardingToASibling)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("results") == true)
    }

    @Test("an extension in this same file is merged rather than hidden")
    func sameFileExtensionIsMerged() {
        // The catalog carries names, not files, so a same-file extension appears in it exactly as
        // a cross-file one does. The visitor subtracts what it can see; getting that wrong would
        // silence every type with a same-file extension — a new over-gate introduced by the fix
        // for an under-gate.
        //
        // `results` forwards to `header`, which is right here in the file, so its dependency set
        // is known and the finding stands.
        let source = """
        struct Screen: View {
            let title: String
            @State private var isBusy = false
            private var results: some View { header }
            var body: some View {
                VStack {
                    results
                    Text(title)
                    if isBusy { ProgressView() }
                }
            }
        }

        extension Screen {
            var header: some View { Text(title) }
        }
        """
        let catalog = ExtensionMemberCatalog(membersByType: ["Screen": ["header"]])
        let issues = filteredIssues(source, extensionMembers: catalog)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("results") == true)
    }

    @Test("a view property declared in an extension is still not reported")
    func extensionDeclaredPropertyIsNotItselfReported() {
        // A standing limit, pinned so it stays a decision. Merging an extension's members feeds
        // the dependency walk; it does not put the extension's own properties in scope for
        // reporting, because `isInsideViewType` is set by entering the type declaration. Reporting
        // them would be a coverage *increase* on a rule this pass is narrowing, and belongs to its
        // own measurement.
        let source = """
        struct Screen: View {
            let title: String
            @State private var isBusy = false
            var body: some View {
                VStack {
                    header
                    Text(title)
                    if isBusy { ProgressView() }
                }
            }
        }

        extension Screen {
            var header: some View { Text(title) }
        }
        """
        #expect(filteredIssues(source).isEmpty)
    }

    @Test("a property that reaches no hidden member is still reported")
    func unrelatedPropertyIsStillReported() {
        // The gate has to be per-property, not per-type: a file with one split-off sibling must
        // not go silent on the properties that never touch it.
        let source = """
        struct Screen: View {
            let title: String
            @State private var isBusy = false
            private var caption: some View { Text(title) }
            private var results: some View { summaryCards }
            var body: some View {
                VStack {
                    caption
                    results
                    if isBusy { ProgressView() }
                }
            }
        }
        """
        let catalog = ExtensionMemberCatalog(membersByType: ["Screen": ["summaryCards"]])
        let issues = filteredIssues(source, extensionMembers: catalog)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("caption") == true)
    }

    @Test("the reach is transitive")
    func reachIsTransitive() {
        // A wrapper forwarding to a wrapper forwarding to an unseen sibling knows no more than the
        // sibling does — the same transitivity the dependency walk and the capture gate use.
        let source = """
        struct Screen: View {
            let title: String
            @State private var isBusy = false
            private var inner: some View { summaryCards }
            private var outer: some View { inner }
            var body: some View {
                VStack {
                    outer
                    Text(title)
                    if isBusy { ProgressView() }
                }
            }
        }
        """
        let catalog = ExtensionMemberCatalog(membersByType: ["Screen": ["summaryCards"]])
        #expect(filteredIssues(source, extensionMembers: catalog).isEmpty)
    }

    @Test("the catalog collects var and func names per extended type")
    func catalogCollectsMembers() {
        let source = """
        extension Screen {
            var header: some View { Text("x") }
            func reload() { }
            private struct Row: View {
                var body: some View { Text("row") }
            }
        }

        extension Other {
            var footer: some View { Text("y") }
        }
        """
        let catalog = ExtensionMemberCatalog.build(from: [Parser.parse(source: source)])
        // `body` belongs to the nested `Row`, not to `Screen`, so it is not collected here.
        #expect(catalog.members(on: "Screen") == ["header", "reload"])
        #expect(catalog.members(on: "Other") == ["footer"])
        #expect(catalog.members(on: "Absent").isEmpty)
    }
}

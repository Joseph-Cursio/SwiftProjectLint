import Foundation
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// A property whose contents a container **decomposes** is not extractable into a `View` struct.
///
/// `confirmationDialog(actions:)`, `alert(actions:)`, `Menu(content:)` and `contextMenu` read a
/// collection of buttons out of the builder they are handed; `ToolbarItem`, `ToolbarItemGroup` and
/// `.toolbar` read a collection of toolbar items out of theirs. Wrapping either in a `View`
/// interposes a container those APIs are not specified to accept, so following the rule's advice
/// there changes what the app does rather than only how it redraws — the one place this rule could
/// break something.
///
/// The dialog half was found on MacCloud_client_iOS: `FileListView` had three such properties and
/// the rule reported all three. Lowering them to `info` for carrying `@ViewBuilder` is not the same
/// as declining. The toolbar half was found on SwiftLintRuleStudio, where `ViolationInspectorView`
/// composes five properties into one `ToolbarItemGroup` — one of them a `Group` of two `Button`s,
/// which places two items and would place one after extraction.
@Suite("A decomposed container's contents are not an extractable subview")
struct ComputedViewButtonCollectionTests {

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

    @Test("a toolbar item group's contents are not reported")
    func toolbarItemGroupContentsAreNotReported() {
        // `ToolbarItemGroup` places one item per view in its builder. `navigationButtons` is two
        // buttons and places two; a `View` struct wrapping them is one view and places one. The
        // shape is SwiftLintRuleStudio's `ViolationInspectorView`, reduced.
        #expect(filteredIssues("""
        struct Inspector: View {
            let title: String
            @State private var showing = false
            @ViewBuilder
            private var navigationButtons: some View {
                Button("Next") { }
                Button("Previous") { }
            }
            @ToolbarContentBuilder
            private var toolbarContent: some ToolbarContent {
                ToolbarItemGroup(placement: .primaryAction) {
                    navigationButtons
                }
            }
            var body: some View {
                VStack {
                    Text(title)
                    Toggle("", isOn: $showing)
                }
                .toolbar { toolbarContent }
            }
        }
        """).isEmpty)
    }

    @Test("a single toolbar item's content is not reported either")
    func toolbarItemContentIsNotReported() {
        // Coarse in the safe direction, exactly as `alert`'s `message:` closure is. This one view
        // could be extracted without changing the item count, and is spared with the rest.
        #expect(filteredIssues("""
        struct Sheet: View {
            let title: String
            @State private var query = ""
            private var searchField: some View {
                TextField("Search", text: .constant(""))
            }
            @ToolbarContentBuilder
            private var toolbar: some ToolbarContent {
                ToolbarItem(placement: .primaryAction) { searchField }
            }
            var body: some View {
                Text(title).toolbar { toolbar }
            }
        }
        """).isEmpty)
    }

    @Test("a property used in body and never in a toolbar is still reported")
    func nonToolbarSiblingIsStillReported() {
        // The control. A file containing a toolbar must not go silent on the properties that have
        // nothing to do with it — the same failure the dialog gate's receiver test guards against.
        let issues = filteredIssues("""
        struct Screen: View {
            let title: String
            @State private var showing = false
            private var header: some View { Text("Files") }
            private var closeButton: some View { Button("Close") { } }
            @ToolbarContentBuilder
            private var toolbarContent: some ToolbarContent {
                ToolbarItem(placement: .cancellationAction) { closeButton }
            }
            var body: some View {
                VStack {
                    header
                    Text(title)
                    Toggle("", isOn: $showing)
                }
                .toolbar { toolbarContent }
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("header") == true)
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

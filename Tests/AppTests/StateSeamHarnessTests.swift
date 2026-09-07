import SwiftUI
import Testing
import ViewInspector

/// Does extracting a callback body into a named method make the effect assertable?
///
/// `Unreachable Effect Closure` is a `testability` rule and its description makes a testability
/// claim: *"No test can fire the callback, so the effect has no seam to be observed through;
/// naming it gives the effect one."* Fifty of its 87 corpus findings write to nothing but the
/// enclosing view's own `@State`, so the claim has to hold for that case or the rule is asking
/// for 50 refactors that buy nothing.
///
/// This is the harness rather than the argument. It builds both halves — the reported form and
/// the form the rule asks for — and tries every route a test has to the state afterwards.
@Suite("Does a named method give a @State write a seam?")
@MainActor
struct StateSeamHarnessTests {

    /// The shape the rule reports, and the shape it asks for, in one view.
    private struct SubjectView: View {
        @State private var flag = false

        /// Readable from a test. The point of the harness is that this still answers `false`
        /// after a write, so exposing it is not what is missing.
        var isOn: Bool { flag }

        /// The extraction the rule's suggestion describes: the body lifted into a named method.
        func present() { flag = true }

        var body: some View {
            VStack {
                Button("reported") { flag = true }
                Button("extracted", action: present)
                Text(flag ? "on" : "off")
            }
        }
    }

    @Test("Calling the extracted method on an uninstalled view does not change the state")
    func extractedMethodOnUninstalledView() {
        let view = SubjectView()
        #expect(view.isOn == false)

        view.present()

        // The whole of the rule's promise, tested directly. `@State`'s storage is allocated by
        // SwiftUI when it installs the view; before that the setter has nowhere to write and the
        // getter answers from the initial value. Naming the mutation changes none of that.
        #expect(view.isOn == false)
    }

    @Test("Reading the state back through the rendered body also shows nothing")
    func extractedMethodThroughRenderedBody() throws {
        let view = SubjectView()
        view.present()

        // Not a limitation of the reader: the body renders from the same uninstalled storage.
        let text = try view.inspect().find(ViewType.Text.self).string()
        #expect(text == "off")
    }

    @Test("Firing the callback does not reach it either, and reaches it equally badly both ways")
    func firingTheCallbackReachesNothing() throws {
        // Without a control the two tests above prove only that nothing works, which is not a
        // finding. So: fire each button and read the state back.
        let inline = SubjectView()
        try inline.inspect().find(button: "reported").tap()
        let afterInline = try inline.inspect().find(ViewType.Text.self).string()

        let extracted = SubjectView()
        try extracted.inspect().find(button: "extracted").tap()
        let afterExtracted = try extracted.inspect().find(ViewType.Text.self).string()

        // Both read "off". Tapping an unhosted view runs the action, the action writes, and the
        // write goes nowhere — the same as calling the method directly. The only route that
        // observes this state at all is `ViewHosting.host`, and that route goes through SwiftUI's
        // storage rather than through the name, so it works identically for both forms.
        //
        // Which is the finding stated as sharply as it can be: the seam a test uses is the
        // *button*, and the button exists in both forms. The method exists in one and adds
        // nothing.
        #expect(afterInline == "off")
        #expect(afterExtracted == "off")
    }

    @Test("And a model write is reachable without any of this")
    func aModelWriteNeedsNoView() {
        // The other half of the corpus, for contrast. Thirty-four of the 87 findings write to an
        // object the view does not own. Lifting one of those onto the model gives a method a test
        // calls directly — no view, no hosting, no inspection.
        @MainActor
        final class Selection {
            private(set) var chosen: Int?
            func clear() { chosen = nil }
            func choose(_ value: Int) { chosen = value }
        }

        let selection = Selection()
        selection.choose(3)
        #expect(selection.chosen == 3)
        selection.clear()
        #expect(selection.chosen == nil)
    }

    // MARK: - Which wrappers the finding actually holds

    private struct BindingSubject: View {
        @Binding var flag: Bool
        func present() { flag = true }
        var body: some View { Button("go", action: present) }
    }

    @Test("A @Binding write IS observable, so it must not be gated")
    func bindingWriteIsObservable() {
        // Fifteen of the corpus write targets are `@Binding`. A binding is the parent's storage,
        // and a test supplies its own — so the write lands somewhere the test owns and can read.
        // This is the case that keeps the gate from being "any property wrapper".
        final class Box: @unchecked Sendable { var value = false }
        let box = Box()
        let view = BindingSubject(
            flag: Binding(get: { box.value }, set: { box.value = $0 })
        )

        view.present()

        #expect(box.value == true)
    }

    private struct StorageSubject: View {
        @AppStorage("uec.harness.flag") private var flag = false
        var isOn: Bool { flag }
        func present() { flag = true }
        var body: some View { Button("go", action: present) }
    }

    @Test("An @AppStorage write IS observable, so it must not be gated either")
    func appStorageWriteIsObservable() {
        // Four of the corpus write targets are `@AppStorage`. Unlike `@State`, its setter writes
        // straight through to the defaults store, which a test reads without any view at all.
        UserDefaults.standard.removeObject(forKey: "uec.harness.flag")
        defer { UserDefaults.standard.removeObject(forKey: "uec.harness.flag") }

        let view = StorageSubject()
        #expect(view.isOn == false)

        view.present()

        #expect(UserDefaults.standard.bool(forKey: "uec.harness.flag") == true)
        #expect(view.isOn == true)
    }

    private struct FocusSubject: View {
        private enum Field: Hashable { case name }
        @FocusState private var focus: Field?
        var isFocused: Bool { focus == .name }
        func focusName() { focus = .name }
        var body: some View { TextField("name", text: .constant("")).focused($focus, equals: .name) }
    }

    @Test("@FocusState behaves like @State, measured rather than assumed")
    func focusStateWriteIsNotObservable() {
        // No corpus finding writes `@FocusState`, so this is the one wrapper the gate covers on
        // mechanism rather than on evidence. Measuring it is cheaper than arguing about it.
        let view = FocusSubject()
        #expect(view.isFocused == false)

        view.focusName()

        #expect(view.isFocused == false)
    }
}

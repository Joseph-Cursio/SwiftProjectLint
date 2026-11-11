import SwiftProjectLintModels
import Testing

extension PositionalViewLookupChainShapeTests {
    // MARK: - ViewInspector's semantics

    @Test("findAll's [0] is .first; .last and other indices are ordinals")
    func matchOrdinals() {
        let issues = analyzeTest("""
            _ = try sut.inspect().findAll(ViewType.Button.self)[0].tap()
            _ = try sut.inspect().findAll(ViewType.Button.self).first?.tap()
            _ = try sut.inspect().findAll(ViewType.Button.self).last?.tap()
            _ = try sut.inspect().find(ViewType.Button.self, skipFound: 2).tap()
        """)
        #expect(issues.map(\.lineNumber) == [7, 8])
    }

    @Test(".first and .last on a container are children by position, except ForEach rows")
    func containerFirstLast() {
        let issues = analyzeTest("""
            _ = try sut.inspect().vStack().first?.text().string()
            _ = try sut.inspect().find(ViewType.ForEach.self).first?.text().string()
        """)
        #expect(issues.map(\.lineNumber) == [5])
    }

    @Test("toolbar items and bar items are picked in declared order")
    func orderedSlots() {
        let issues = analyzeTest("""
            _ = try sut.inspect().find(ViewType.NavigationStack.self).toolbar().item(2).button()
            _ = try sut.inspect().find(ViewType.NavigationStack.self).toolbar().item().button()
            _ = try sut.inspect().vStack().navigationBarItems(1).hStack()
        """)
        #expect(issues.map(\.lineNumber) == [5, 7])
    }

    /// `navigationBarItems()` never reaches the bar items: it strips the wrapper
    /// `.navigationBarItems(…)` put around the receiver's child and returns the view the modifier
    /// was applied to — on a container its first child, the view `navigationBarItems(0)` reaches —
    /// so it moves a level as `form()` does, and the accessor after it casts that view in place, as
    /// `list()` does here. `item()` and `itemGroup()` start a new anchor instead, as `orderedSlots`
    /// pins.
    @Test("navigationBarItems() reaches a container's child, so it counts as a level")
    func barItemsCountAsALevel() {
        let issues = analyzeTest("""
            _ = try sut.inspect().navigationView().navigationBarItems().list()
            _ = try sut.inspect().vStack().navigationBarItems().hStack()
            _ = try sut.inspect().vStack().navigationBarItems(AnyView.self).hStack()
            _ = try sut.inspect().find(ViewType.NavigationView.self).navigationBarItems().list()
            _ = try sut.inspect().find(viewWithAccessibilityIdentifier: "list").navigationBarItems().hStack().text()
            _ = try sut.inspect().navigationView().navigationBarItems(0)
            _ = try sut.inspect().find(ViewType.NavigationStack.self).toolbar().item().vStack().text()
            _ = try sut.inspect().toolbar().itemGroup().text()
        """)
        #expect(issues.map(\.lineNumber) == [5, 6, 7, 10, 11])
        #expect(issues.first?.message.contains("`.navigationBarItems()` walks a further level") == true)
    }

    /// `inspect()` hands back the inspected view itself, and `navigationBarItems()` takes its only
    /// child without the fallback to an app view's body that `x()` has: on a SwiftUI view a
    /// factory built, the step unwraps in place, as on a found view. An index past 0 still picks.
    @Test("navigationBarItems() on a bare inspect() unwraps in place")
    func barItemsOnRootUnwrapInPlace() {
        let issues = analyzeTest("""
            _ = try sut.inspect().navigationBarItems().list().text()
            _ = try makeScreen().inspect().navigationBarItems(VStack<Text>.self).vStack().text()
            _ = try sut.inspect().navigationBarItems(0).list().text()
            _ = try sut.inspect().navigationBarItems().list().text(1)
            _ = try sut.inspect().navigationBarItems(1)
        """)
        #expect(issues.map(\.lineNumber) == [8, 9])
    }

    @Test("modifier(T.self) is a slot and the walk after it is read")
    func modifierSlot() {
        let issues = analyzeTest("    _ = try sut.inspect().modifier(CardModifier.self).hStack().text(1)")
        #expect(issues.first?.message.contains("`.text(1)`") == true)
    }

    @Test("a function handed to a container's forEach is the Sequence method")
    func sequenceForEach() {
        let issues = analyze("""
        func checkAccessible(_ view: InspectableView<ViewType.ClassifiedView>) {}

        func testEach() throws {
            try CounterView().inspect().vStack().forEach(checkAccessible)
            let index = 1
            _ = try CounterView().inspect().list().forEach(index)
        }
        """)
        #expect(issues.map(\.lineNumber) == [8])
    }

    @Test("a parameter typed InspectableView<ViewType.ForEach> indexes rows")
    func typedDataReceivers() {
        let issues = analyze("""
        private func row(_ rows: InspectableView<ViewType.ForEach>, at index: Int) throws
            -> InspectableView<ViewType.ClassifiedView> {
            try rows[index]
        }

        private extension InspectableView where View == ViewType.ForEach {
            func third() throws -> InspectableView<ViewType.ClassifiedView> { try self[2] }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("a dialog's action buttons are layout, not data, outside an action sheet")
    func unavailableViewActions() {
        let issues = analyzeTest("""
            _ = try sut.inspect().find(ViewType.ContentUnavailableView.self).actions().button(1)
            _ = try sut.inspect().find(ViewType.ActionSheet.self).button(1)
        """)
        #expect(issues.map(\.lineNumber) == [5])
    }

    @Test("only ViewInspector's inspect labels make a root")
    func foreignInspect() {
        let issues = analyzeTest("""
            let tree = debugger.inspect(node: root)
            _ = tree.list(0)
            let report = analyzer.inspect(using: options) { item in item.text(3) }
            _ = try PillStyle().inspect(isPressed: true).hStack().styleConfigurationLabel(1)
        """)
        #expect(issues.map(\.lineNumber) == [8])
    }

    @Test("a dictionary keyed by name is not a positional subscript")
    func namedSubscript() {
        let issues = analyze("""
        func titles(_ views: [String: InspectableView<ViewType.ClassifiedView>]) throws -> String {
            try views["title"]!.text().string()
        }
        """)
        #expect(issues.isEmpty)
    }

    // MARK: - Test-owned subjects

    @Test("a relay over a test-declared view walks the test's own layout")
    func ownedRelay() {
        let issues = analyze("""
        private struct OwnedView: View {
            var body: some View { VStack { Text("a"); Text("b") } }
        }

        func testRelay() throws {
            let sut = OwnedView()
            _ = sut.inspection.inspect { view in
                try view.vStack().text(0).string()
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("an app view reached through a test-declared host is not owned")
    func hostedAppView() {
        let issues = analyze("""
        private struct Host: View {
            var body: some View { CounterView().environmentObject(Model()) }
        }

        private final class MockStore {
            func makeContentView() -> ContentView { ContentView(store: self) }
        }

        func testHost() throws {
            _ = try Host().inspect().find(CounterView.self).vStack().hStack(1)
            _ = try MockStore().makeContentView().inspect().vStack().hStack(1)
        }
        """)
        #expect(issues.map(\.lineNumber) == [12, 13])
    }

    @Test("ownership follows a declared type, Outer.Inner and .init")
    func ownedSpellings() {
        let issues = analyze("""
        private struct OwnedView: View {
            var body: some View { VStack { Text("a"); Text("b") } }
        }
        enum Outer {
            struct Inner: View { var body: some View { VStack { Text("a") } } }
        }

        final class OwnershipTests: XCTestCase {
            var owned: OwnedView!

            func testSpellings() throws {
                _ = try owned.inspect().vStack().text(1)
                _ = try Outer.Inner().inspect().vStack().text(1)
                _ = try OwnedView.init().inspect().vStack().text(1)
            }
        }
        """)
        #expect(issues.isEmpty)
    }
}

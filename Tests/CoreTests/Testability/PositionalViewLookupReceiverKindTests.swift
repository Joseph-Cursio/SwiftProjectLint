@testable import Core
import Testing

/// Whether an accessor moves depends on what it is called on: a found view's only child is
/// itself, a custom view's is its body, a SwiftUI container's are its layout. These pin the
/// receiver each ViewInspector step hands back, from a second review round's fixtures.
@Suite
struct PositionalViewLookupReceiverKindTests {

    private func analyze(_ body: String) -> [LintIssue] {
        positionalViewLookupIssues(in: body)
    }

    private func analyzeTest(_ statements: String) -> [LintIssue] {
        positionalViewLookupIssues(inTestBody: statements)
    }

    // MARK: - Found views

    @Test("every find that returns the found view casts in place")
    func foundViewForms() {
        let issues = analyzeTest("""
            _ = try sut.inspect().find(relation: .parent, where: { _ in true }).vStack(0)
            _ = try sut.inspect().find(traversal: .depthFirst) { _ in true }.vStack(0)
            _ = try sut.inspect().find(viewWithId: 1)[0].text()
            _ = try sut.inspect().find(viewWithTag: 2).first?.text()
        """)
        #expect(issues.isEmpty)
    }

    @Test("a found view's first level below is as free as a typed find's")
    func foundViewFreeLevel() {
        let issues = analyzeTest("""
            _ = try sut.inspect().find(viewWithAccessibilityIdentifier: "s").scrollView().vStack()
            _ = try sut.inspect().find(ViewType.ScrollView.self).vStack()
        """)
        #expect(issues.isEmpty)
    }

    // MARK: - Custom views and relays

    @Test("a custom view's only child is its body, so x(0) is x()")
    func customViewIndexZero() {
        let issues = analyzeTest("""
            _ = try sut.inspect().find(Row.self).vStack(0)
            _ = try sut.inspect().view(CounterView.self).vStack(0)
        """)
        #expect(issues.isEmpty)
    }

    @Test("a relay's view and a modifier root unwrap to their body")
    func relayAndModifierDescend() {
        let issues = analyzeTest("""
            sut.inspect { view in _ = try view.view(Child.self).vStack() }
            _ = try CardModifier().inspect().view(Child.self).vStack()
        """)
        #expect(issues.map(\.lineNumber) == [5, 6])
    }

    @Test("relays forwarding file and line, or passing inspection:, are relays")
    func relayLabels() {
        let issues = analyzeTest("""
            sut.inspect(function: #function, file: #file, line: #line) { view in _ = try view.vStack().hStack(1) }
            sut.inspect(inspection: { view in _ = try view.vStack().hStack(2) })
            _ = sut.inspection.inspect(after: 0.1, file: #file, line: #line) { view in _ = try view.vStack().hStack(3) }
        """)
        #expect(issues.map(\.lineNumber) == [5, 6, 7])
    }

    @Test("a walk before a relay in the same chain is kept")
    func walkBeforeRelay() {
        let issues = analyzeTest("""
            try sut.inspect().vStack().view(Row.self, 1).actualView().inspect { row in _ = try row.text() }
        """)
        #expect(issues.first?.message.contains("`.view(Row.self, 1)`") == true)
    }

    // MARK: - Rows and matches

    @Test("a ForEach row's own children are layout")
    func forEachRowChildren() {
        let issues = analyzeTest("""
            _ = try sut.inspect().find(ViewType.ForEach.self)[2].text(1)
            _ = try sut.inspect().find(ViewType.ForEach.self).first?.text(1)
            for row in try sut.inspect().find(ViewType.ForEach.self) { _ = try row.text(1) }
        """)
        #expect(issues.map(\.lineNumber) == [5, 6, 7])
    }

    @Test("findAll of a type yields views of that type, not found views")
    func typedMatches() {
        let issues = analyzeTest("""
            _ = try sut.inspect().findAll(ViewType.HStack.self)[0].text(0)
            for row in try sut.inspect().findAll(ViewType.HStack.self) { _ = try row.text(0) }
            try sut.inspect().findAll(ViewType.HStack.self).forEach { row in _ = try row.text(1) }
        """)
        #expect(issues.map(\.lineNumber) == [5, 6, 7])
    }

    @Test("a generic InspectableView receiver could be any container")
    func genericReceiver() {
        let issues = analyze("""
        func firstText<V: MultipleViewContent>(_ view: InspectableView<V>) throws -> String {
            try view.text(0).string()
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("an annotation stands in for an initializer the rule cannot read")
    func annotationFallback() {
        let issues = analyzeTest("""
            let stack: InspectableView<ViewType.VStack> = try makeStack()
            _ = try stack.text(0)
            let rows: InspectableView<ViewType.ForEach> = try makeRows()
            _ = try rows.text(2)
        """)
        #expect(issues.map(\.lineNumber) == [6])
    }

    @Test("a closure or function value handed to forEach is not an index")
    func functionValuesToForEach() {
        let issues = analyze("""
        func runAll(_ check: (InspectableView<ViewType.ClassifiedView>) throws -> Void) throws {
            let assertAccessible: (InspectableView<ViewType.ClassifiedView>) throws -> Void = { _ in }
            let describe = { (view: InspectableView<ViewType.ClassifiedView>) in view.pathToRoot }
            try CounterView().inspect().vStack().forEach(assertAccessible)
            _ = try CounterView().inspect().vStack().map(describe)
            try CounterView().inspect().vStack().forEach(check)
        }
        """)
        #expect(issues.isEmpty)
    }

    // MARK: - Ownership

    @Test("the order of matches is the searched tree's")
    func matchOwnership() {
        let issues = analyze("""
        private struct OwnedHost: View { var body: some View { AppRow() } }
        private struct OwnedLeaf: View { var body: some View { Text("x") } }
        private struct OwnedStack: View { var body: some View { VStack { OwnedLeaf(); OwnedLeaf() } } }

        func testMatches() throws {
            _ = try OwnedHost().inspect().findAll(AppRow.self)[1]
            _ = try app.inspect().findAll(OwnedLeaf.self)[1]
            _ = try OwnedStack().inspect().findAll(OwnedLeaf.self)[1]
        }
        """)
        #expect(issues.map(\.lineNumber) == [8, 9])
    }

    @Test("a modifier, a re-inspected view and a generic type decide their own ownership")
    func ownershipFollowsTheWalkedType() {
        let issues = analyze("""
        private struct OwnedCard: ViewModifier { func body(content: Content) -> some View { content } }
        private struct OwnedLeaf: View { var body: some View { Text("x") } }
        private struct OwnedRow<Value>: View { var body: some View { Text("x") } }

        func testOwnership(app: AppScreen) throws {
            _ = try app.inspect().modifier(OwnedCard.self).vStack().text(1)
            _ = try app.inspect().find(OwnedLeaf.self).actualView().inspect().vStack().text(1)
            _ = try app.inspect().find(OwnedRow<Int>.self).vStack().text(1)
            _ = try OwnedLeaf().inspect().modifier(AppCard.self).vStack().text(1)
        }

        func ownedLeafText(_ view: InspectableView<ViewType.View<OwnedLeaf>>) throws -> String {
            try view.vStack().text(1).string()
        }
        """)
        #expect(issues.map(\.lineNumber) == [11])
    }
}

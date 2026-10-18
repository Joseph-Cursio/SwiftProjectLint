@testable import Core
import Testing

/// Shapes from realistic test suites that a final review found misread: the finder helpers the
/// rule's own doc recommends, loops that compare every match in order, styles and SwiftUI views
/// inspected directly, and fixtures built by factories.
@Suite
struct PositionalViewLookupRealisticShapeTests {

    private func analyze(_ body: String) -> [LintIssue] {
        positionalViewLookupIssues(in: body)
    }

    private func analyzeTest(_ statements: String) -> [LintIssue] {
        positionalViewLookupIssues(inTestBody: statements)
    }

    @Test("a finder helper named like an accessor is the helper, not ViewInspector's")
    func finderHelperNamedLikeAccessor() {
        let issues = analyze("""
        private enum A11y: String { case increment, count }

        private extension InspectableView {
            func button(_ id: A11y) throws -> InspectableView<ViewType.Button> {
                try find(viewWithAccessibilityIdentifier: id.rawValue).button()
            }
            func item(_ index: Int) throws -> InspectableView<ViewType.ClassifiedView> {
                try find(viewWithId: index)
            }
        }

        func testHelpers() throws {
            let toggleID = "toggle"
            try sut.inspect().button(.increment).tap()
            _ = try sut.inspect().item(toggleID.count)
            _ = try sut.inspect().vStack().button(1)
        }
        """)
        #expect(issues.map(\.lineNumber) == [18])
    }

    @Test("a loop over every position compares the whole sequence")
    func loopOverEveryPosition() {
        let issues = analyzeTest("""
            let rows = try sut.inspect().findAll(ShoppingRow.self)
            for (index, name) in expected.enumerated() { #expect(try rows[index].actualView().name == name) }
            let texts = try sut.inspect().vStack()
            for index in texts.indices { _ = try texts.text(index) }
            for position in 0..<rows.count { _ = try rows[position] }
            _ = try rows[2]
        """)
        #expect(issues.map(\.lineNumber) == [10])
    }

    @Test("a style or a SwiftUI view inspected directly is the view itself")
    func styleAndLiteralRoots() {
        let issues = analyzeTest("""
            _ = try CardGroupBoxStyle().inspect().scrollView().vStack()
            _ = try FramedButtonStyle().inspect(isPressed: true).geometryReader().styleConfigurationLabel()
            _ = try NavigationStack { AppScreen() }.inspect().navigationStack().view(AppScreen.self).find(text: "S")
            _ = try AppHost().inspect().scrollView().view(AppScreen.self)
        """)
        #expect(issues.map(\.lineNumber) == [8])
    }

    /// This test used to pin `[0]` and `.first` on a custom view as reaching its body; ViewInspector
    /// gives a custom view every view its body builds, as it gives a sheet.
    @Test("[0] and .first on a custom view pick one of its body's views, as on a sheet")
    func firstChildOfCustomView() {
        let issues = analyzeTest("""
            _ = try sut.inspect().find(RowView.self)[0]
            _ = try sut.inspect().find(RowView.self).first
            _ = try sut.inspect().find(ViewType.Button.self).sheet()[0]
        """)
        #expect(issues.map(\.lineNumber) == [5, 6, 7])
    }

    @Test("re-inspecting found views is linear in the chain's length")
    func reinspectionIsLinear() {
        let links = String(repeating: ".inspect().find(RowView.self).actualView()", count: 20)
        let issues = analyzeTest("    _ = try CounterView()\(links).inspect().vStack().hStack(1)")
        #expect(issues.count == 1)
    }

    @Test("the step entering a test-declared view is judged in the app layout it leaves")
    func enteringOwnedLayout() {
        let issues = analyze("""
        private struct ProbeContent: View { var body: some View { Text("x") } }

        func testCard() throws {
            let card = AppCard { ProbeContent() }
            _ = try card.inspect().scrollView().view(ProbeContent.self)
        }
        """)
        #expect(issues.map(\.lineNumber) == [7])
    }

    @Test("a capture of the same name keeps the binding; a renaming capture rebinds it")
    func captureLists() {
        let issues = analyzeTest("""
            let stack = try sut.inspect().find(ViewType.VStack.self)
            let other = Wrapper()
            DispatchQueue.main.async { [stack] in _ = try? stack.hStack(1) }
            let check = { [stack = other] in _ = try? stack.hStack(2) }
        """)
        #expect(issues.map(\.lineNumber) == [7])
    }

    @Test("ownership follows a factory's declared type, and weak self reaches a property")
    func factoriesAndWeakSelf() {
        let issues = analyze("""
        private struct ProbeView: View {
            static func make() -> ProbeView { ProbeView() }
            var body: some View { HStack { Text("a"); Text("b") } }
        }
        private func makeProbe() -> ProbeView { ProbeView() }

        final class FactoryTests: XCTestCase {
            var stack: InspectableView<ViewType.VStack>!

            func testFactories() throws {
                let probe: ProbeView = makeProbe()
                _ = try probe.inspect().hStack().text(1)
                _ = try ProbeView.make().inspect().hStack().text(1)
                _ = try makeProbe().inspect().hStack().text(1)
                DispatchQueue.main.async { [weak self] in _ = try? self?.stack.hStack(1) }
            }
        }
        """)
        #expect(issues.map(\.lineNumber) == [17])
    }

    @Test("a function member handed to forEach or map is not an index")
    func memberFunctionReferences() {
        let issues = analyze("""
        final class EachTests: XCTestCase {
            static func staticCheck(_ view: InspectableView<ViewType.ClassifiedView>) {}

            func testEach() throws {
                try sut.inspect().vStack().forEach(Self.staticCheck)
                _ = try sut.inspect().vStack().map(String.init(describing:))
            }
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("a step written across lines is quoted on one")
    func multiLineStepQuoted() {
        let issues = analyzeTest("""
            _ = try sut.inspect().tabView().view(GeneralPane.self,
                                                 2)
        """)
        #expect(issues.first?.message.contains("`.view(GeneralPane.self, 2)`") == true)
    }

    @Test("an ordinal over search matches suggests narrowing the search")
    func matchSuggestion() {
        let issues = analyzeTest("    _ = try sut.inspect().findAll(ViewType.Text.self)[2]")
        #expect(issues.first?.suggestion?.contains("Narrow the search") == true)
    }
}

@testable import Core
import Testing

extension PositionalViewLookupVisitorTests {
    // MARK: - Searches and assertions

    @Test("the recommended shape: find by identifier, then one cast")
    func findThenCast() {
        let issues = analyzeTest("""
            let count = try sut.inspect().find(viewWithAccessibilityIdentifier: "count").text().string()
            try sut.inspect().find(button: "+1").tap()
            _ = try sut.inspect().find(ViewType.Button.self).labelView().text().string()
        """)
        #expect(issues.isEmpty)
    }

    @Test("one step after inspect() asserts the body's root type")
    func singleHopFromRoot() {
        let issues = analyzeTest("""
            _ = try sut.inspect().text().string()
            let stack = try sut.inspect().vStack()
            _ = try stack.find(text: "Title")
            #expect((try? sut.inspect().vStack()) == nil)
        """)
        #expect(issues.isEmpty)
    }

    @Test("implicitAnyView() and view(Self.self) do not move")
    func nonMovingSteps() {
        let issues = analyzeTest("""
            _ = try sut.inspect().implicitAnyView().text().string()
            _ = try sut.inspect().view(CounterView.self).vStack()
        """)
        #expect(issues.isEmpty)
    }

    @Test("indices into ForEach rows are data order")
    func forEachRows() {
        let issues = analyzeTest("""
            _ = try sut.inspect().find(ViewType.ForEach.self).view(RowView.self, 2)
            let rows = try sut.inspect().find(ViewType.ForEach.self)
            _ = try rows[3].text().string()
        """)
        #expect(issues.isEmpty)
    }

    @Test("named slots reach a view by role, not position")
    func namedSlots() {
        let issues = analyzeTest("""
            _ = try sut.inspect().sheet().vStack()
            _ = try sut.inspect().find(ViewType.Section.self).header().text().string()
            _ = try sut.inspect().overlay(1).shape()
        """)
        #expect(issues.isEmpty)
    }

    @Test("findAll matched by predicate or mapped is a search")
    func findAllSearches() {
        let issues = analyzeTest("""
            let buttons = try sut.inspect().findAll(ViewType.Button.self)
            let selectAll = buttons.first { (try? $0.labelView().text().string()) == "Select All" }
            let titles = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
            _ = buttons.first
        """)
        #expect(issues.isEmpty)
    }

    @Test("a subject declared in the test file has a layout the test owns")
    func testOwnedFixture() {
        let issues = analyze("""
        private struct GeometryProbe: View {
            var body: some View { GeometryReader { _ in Rectangle() } }
        }

        func testProbe() throws {
            _ = try GeometryProbe().inspect().geometryReader().shape()
            let probe = GeometryProbe().padding()
            _ = try probe.inspect().geometryReader().shape()
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test("a test helper that takes an index is not a ViewInspector accessor")
    func customHelperWithIndex() {
        let issues = analyzeTest("""
            _ = try sut.inspect().pegColor(1)
            _ = try sut.inspect().feedbackPegColor(1)
        """)
        #expect(issues.isEmpty)
    }

    @Test("same-named members on other receivers are not inspected views")
    func unrelatedReceivers() {
        let issues = analyzeTest("""
            let label = UILabel()
            _ = label.text
            let path = IndexPath(row: 0, section: 1)
            _ = path.section
            let items = ["a", "b"]
            _ = items[1]
            var flag = false
            flag.toggle()
        """)
        #expect(issues.isEmpty)
    }

    @Test("SwiftUI modifiers applied before inspect() are not steps")
    func modifiersBeforeInspect() {
        let issues = analyzeTest("""
            let view = Text("x").background(Color.red).overlay { Text("y") }
            _ = try view.inspect().text().string()
        """)
        #expect(issues.isEmpty)
    }

    @Test("a predicate's parameter is a candidate, not a root")
    func findPredicateParameter() {
        let issues = analyzeTest("""
            _ = try sut.inspect().find(ViewType.Button.self) { button in
                try button.labelView().text().string() == "OK"
            }
        """)
        #expect(issues.isEmpty)
    }

    @Test("a file that does not import ViewInspector is never read")
    func withoutImport() {
        let issues = analyze("""
        func testThing() throws {
            _ = try CounterView().inspect().vStack().hStack(1).button(0)
        }
        """, importing: false)
        #expect(issues.isEmpty)
    }
}

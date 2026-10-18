@testable import Core
import Testing

/// What an accessor's argument is: an index, a finder helper's identifier, or a function handed to
/// a container's `forEach`; and when an index in a loop visits every position.
@Suite
struct PositionalViewLookupArgumentTests {

    private func analyze(_ body: String) -> [LintIssue] {
        positionalViewLookupIssues(in: body)
    }

    private func analyzeTest(_ statements: String) -> [LintIssue] {
        positionalViewLookupIssues(inTestBody: statements)
    }

    @Test("a finder helper is matched by its parameters, not only its name")
    func helperSignatures() {
        let issues = analyze("""
        extension InspectableView {
            func find(_ id: String) throws -> InspectableView<ViewType.ClassifiedView> {
                try find(viewWithAccessibilityIdentifier: id)
            }
            func view<T>(_ type: T.Type, id: String) throws -> InspectableView<ViewType.ClassifiedView> {
                try find(viewWithAccessibilityIdentifier: id)
            }
        }

        func testHelpers() throws {
            _ = try sut.inspect().find("increment").button()
            _ = try sut.inspect().find(ViewType.VStack.self).hStack(1)
            _ = try sut.inspect().find(ViewType.Text.self, skipFound: 2)
            _ = try sut.inspect().tabView().view(GeneralPane.self, 2)
            _ = try sut.inspect().view(GeneralPane.self, id: "general").vStack()
        }
        """)
        #expect(issues.map(\.lineNumber) == [14, 15, 16])
    }

    @Test("a String or an identifier's enum case is not an index")
    func identifierArguments() {
        let issues = analyzeTest("""
            let identifier = "increment"
            let name: String = "count"
            try sut.inspect().button(identifier).tap()
            _ = try sut.inspect().text(name).string()
            _ = try sut.inspect().text(A11y.count).string()
            _ = try sut.inspect().text(A11y.count.rawValue).string()
            let position = 1
            _ = try sut.inspect().vStack().text(position)
        """)
        #expect(issues.map(\.lineNumber) == [12])
    }

    @Test("a parameter's declared type says whether it is an index")
    func parameterTypes() {
        let issues = analyze("""
        func tap(_ identifier: String, at position: Int, in sut: CounterView) throws {
            try sut.inspect().button(identifier).tap()
            try sut.inspect().vStack().button(position).tap()
        }
        """)
        #expect(issues.map(\.lineNumber) == [5])
    }

    @Test("an Int property handed to forEach is an index; a method is a function")
    func forEachMembers() {
        let issues = analyze("""
        enum Layout { static let rowsIndex = 1 }

        final class EachTests: XCTestCase {
            let section = 2
            func check(_ view: InspectableView<ViewType.ClassifiedView>) {}

            func testEach() throws {
                let list = try sut.inspect().list()
                _ = try list.forEach(self.section)
                _ = try list.forEach(Layout.rowsIndex)
                try list.forEach(self.check)
            }
        }
        """)
        #expect(issues.map(\.lineNumber) == [11, 12])
    }

    @Test("a loop visits every position only through its own unfiltered variable, up to a count")
    func loopsOverEveryPosition() {
        let issues = analyzeTest("""
            let rows = try sut.inspect().findAll(ViewType.Text.self)
            let stack = try sut.inspect().find(ViewType.VStack.self)
            for index in 0 ..< rows.count { _ = try rows[index].string() }
            for index in (0..<rows.count) { _ = try rows[index] }
            for index in 0...rows.count - 1 { _ = try stack.text(index) }
            for index in 0..<3 { _ = try stack.hStack(index) }
            for index in rows.indices where index == 2 { _ = try rows[index] }
            for index in rows.indices { let index = 2; _ = try stack.text(index) }
            for index in rows.indices { _ = [3, 4].map { index in try? stack.text(index) } }
            for index in rows.indices { if index == 1 { _ = try stack.button(index) } }
            rows.indices.forEach { index in _ = try? rows[index].string() }
            for (index, name) in zip(rows.indices, expected) { _ = try rows[index].string() == name }
        """)
        #expect(issues.map(\.lineNumber) == [10, 11, 12, 13, 14])
    }

    @Test("a nested identifier constant, a String element and a typed closure parameter are not indices")
    func moreIdentifierArguments() {
        let issues = analyzeTest("""
            try sut.inspect().button(AccessibilityID.Counter.increment).tap()
            for id in ["save", "cancel"] { _ = try sut.inspect().button(id) }
            for id in A11y.allCases { _ = try sut.inspect().button(id) }
            let tap: (String) throws -> Void = { id in try sut.inspect().button(id).tap() }
            let read = { (id: String) throws -> String in try sut.inspect().text(id).string() }
            for position in [0, 2] { _ = try sut.inspect().vStack().text(position) }
        """)
        #expect(issues.map(\.lineNumber) == [10])
    }

    @Test("self.x declared elsewhere and an Int-backed raw value are indices")
    func moreIntegerArguments() {
        let issues = analyze("""
        enum Tab: Int { case home, search, settings }

        final class IndexTests: BaseViewTests {
            func testIndices() throws {
                let tabs = try RootView().inspect().find(ViewType.TabView.self)
                _ = try tabs.vStack(self.secondRow)
                _ = try tabs.view(SettingsView.self, Tab.settings.rawValue)
                _ = try tabs.vStack(A11y.count.rawValue)
            }
        }
        """)
        #expect(issues.map(\.lineNumber) == [8, 9])
    }

    @Test("an argument that is certainly an Int is not a String helper's")
    func helperTakesNoInteger() {
        let issues = analyze("""
        extension InspectableView {
            func text(_ id: String) throws -> InspectableView<ViewType.Text> {
                try find(viewWithAccessibilityIdentifier: id).text()
            }
        }

        func testHelpers() throws {
            let stack = try sut.inspect().find(ViewType.VStack.self)
            let second = 1
            _ = try stack.text(second)
            _ = try stack.text(second + 1)
            for index in 0..<3 { _ = try stack.text(index) }
            _ = try stack.text("title")
        }
        """)
        #expect(issues.map(\.lineNumber) == [12, 13, 14])
    }

    @Test("a comparison, a ternary or a concatenation is not certainly an Int, so a String helper still fits")
    func helperTakesNonArithmeticSequence() {
        let issues = analyze("""
        extension InspectableView {
            func button(_ title: String) throws -> InspectableView<ViewType.Button> {
                try find(button: title)
            }
        }

        func testHelpers(pages: Int) throws {
            let stack = try sut.inspect().find(ViewType.VStack.self)
            let primary = ["Save"]
            let extra = ["Cancel"]
            _ = try stack.button(pages > 1 ? "Next" : "Done")
            for title in primary + extra { _ = try stack.button(title) }
            _ = try stack.button(pages * 2)
            _ = try stack.button(pages + 1)
            for index in 1...3 { _ = try stack.button(index) }
        }
        """)
        #expect(issues.map(\.lineNumber) == [15, 16, 17])
    }

    @Test("an element of an array of closures handed to forEach is a function")
    func closureElementsToForEach() {
        let issues = analyzeTest("""
            let stack = try sut.inspect().find(ViewType.VStack.self)
            let checks: [(InspectableView<ViewType.ClassifiedView>) throws -> Void] = []
            for check in checks { try stack.forEach(check) }
        """)
        #expect(issues.isEmpty)
    }
}

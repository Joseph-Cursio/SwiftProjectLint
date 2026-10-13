@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Runs Positional View Lookup alone over `body`, prefixed with `import ViewInspector`.
func positionalViewLookupIssues(in body: String, importing: Bool = true) -> [LintIssue] {
    let source = (importing ? "import ViewInspector\n\n" : "") + body
    let visitor = PositionalViewLookupVisitor(patternCategory: .testability)
    let syntax = Parser.parse(source: source)
    visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "ViewTests.swift", tree: syntax))
    visitor.setFilePath("ViewTests.swift")
    visitor.walk(syntax)
    return visitor.detectedIssues.filter { $0.ruleName == .positionalViewLookup }
}

/// Wraps statements in a test function with an app view `sut` in scope; the first statement is
/// on line 5.
func positionalViewLookupIssues(inTestBody statements: String) -> [LintIssue] {
    positionalViewLookupIssues(in: """
    func testThing() throws {
        let sut = CounterView()
    \(statements)
    }
    """)
}

/// The shapes an adversarial review of the rule found it misreading, each reproduced through the
/// CLI first: how a chain is delimited, which bindings carry it, and what ViewInspector's API
/// actually does at each step.
@Suite
struct PositionalViewLookupChainShapeTests {

    private func analyze(_ body: String) -> [LintIssue] {
        positionalViewLookupIssues(in: body)
    }

    private func analyzeTest(_ statements: String) -> [LintIssue] {
        positionalViewLookupIssues(inTestBody: statements)
    }

    // MARK: - Where a chain ends

    @Test("a chain ending in a property is read")
    func propertyTail() {
        let issues = analyzeTest("""
            #expect(try sut.inspect().list().forEach(0).count == 1)
            let path = try sut.inspect().vStack().hStack(1).pathToRoot
            XCTAssertTrue(try sut.inspect().vStack().button(1).isAbsent)
        """)
        #expect(issues.map(\.lineNumber) == [5, 6, 7])
    }

    @Test("a parenthesised or unwrapped chain is reported once")
    func wrappedChainOnce() {
        let issues = analyzeTest("""
            _ = (try sut.inspect().vStack().text(0)).string()
            _ = (try? sut.inspect().vStack().text(1))?.string()
            let row = try XCTUnwrap(try? sut.inspect().vStack().hStack(1))
            let cell = try #require(try? sut.inspect().vStack().hStack(2))
        """)
        #expect(issues.map(\.lineNumber) == [5, 6, 7, 8])
    }

    @Test("inspect() again mid-chain keeps the walk before it")
    func reinspectKeepsEarlierStep() {
        let issues = analyzeTest("""
            _ = try sut.inspect().vStack().hStack(1).view(Row.self).actualView().inspect().text()
        """)
        #expect(issues.first?.message.contains("`.hStack(1)`") == true)
    }

    // MARK: - Bindings

    @Test("a pick is reported once; one step on the picked view is not a second walk")
    func onePickOneReport() {
        let issues = analyzeTest("""
            let stack = try sut.inspect().vStack()
            let second = try stack[1]
            _ = try second.text().string()
            let cell = try sut.inspect().find(ViewType.List.self).view(Cell.self, 2)
            _ = try cell.vStack()
        """)
        #expect(issues.map(\.lineNumber) == [6, 8])
    }

    @Test("an annotated local keeps its initializer's walk")
    func annotatedLocal() {
        let issues = analyzeTest("""
            let stack: InspectableView<ViewType.ClassifiedView> = try sut.inspect().navigationStack()
            _ = try stack.vStack()
        """)
        #expect(issues.map(\.lineNumber) == [6])
    }

    @Test("a closure parameter typed InspectableView is a root")
    func typedClosureParameter() {
        let issues = analyzeTest("""
            try check { (view: InspectableView<ViewType.ClassifiedView>) in
                _ = try view.vStack().text(1)
            }
        """)
        #expect(issues.count == 1)
    }

    @Test("a later condition sees an earlier condition's binding")
    func conditionChain() {
        let issues = analyzeTest("""
            guard let stack = try? sut.inspect().vStack(), let button = try? stack.button(1) else { return }
            if let row = try? sut.inspect().vStack(), let label = try? row.text(2) { _ = label }
        """)
        #expect(issues.map(\.lineNumber) == [5, 6])
    }

    @Test("self.property reads the stored property")
    func selfProperty() {
        let issues = analyze("""
        final class CounterTests: XCTestCase {
            var inspected: InspectableView<ViewType.ClassifiedView>!

            func testSelfQualified() throws {
                _ = try self.inspected.vStack().text(0)
            }
        }
        """)
        #expect(issues.count == 1)
    }

    @Test("a binding inside #if is found")
    func bindingInsideIfConfig() {
        let issues = analyzeTest("""
            #if compiler(>=6.1)
            let stack = try sut.inspect().vStack()
            #else
            let stack = try sut.inspect().implicitAnyView().vStack()
            #endif
            _ = try stack.text(1)
        """)
        #expect(issues.map(\.lineNumber) == [10])
    }

    @Test("a name rebound by a pattern shadows the inspected local")
    func patternShadowing() {
        let issues = analyzeTest("""
            let row = try sut.inspect().find(ViewType.HStack.self)
            for (index, row) in labels.enumerated() { _ = row.text(index) }
            switch makeResult() {
            case .success(let row): _ = row.text(2)
            default: break
            }
            if case .some(let row) = makeOptional() { _ = row.button(1) }
            do { try work() } catch let row as Labelish { _ = row.label(2) }
        """)
        #expect(issues.isEmpty)
    }

    @Test("a module-qualified InspectableView extension is recognised")
    func qualifiedExtension() {
        let issues = analyze("""
        extension ViewInspector.InspectableView {
            func row() throws { _ = try vStack().hStack(1) }
        }

        extension InspectableViewFactory {
            func make() throws { _ = try vStack().hStack(1) }
        }
        """)
        #expect(issues.map(\.lineNumber) == [4])
    }

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

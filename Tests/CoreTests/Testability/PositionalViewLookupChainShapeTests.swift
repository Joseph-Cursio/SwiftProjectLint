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

    func analyze(_ body: String) -> [LintIssue] {
        positionalViewLookupIssues(in: body)
    }

    func analyzeTest(_ statements: String) -> [LintIssue] {
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
}

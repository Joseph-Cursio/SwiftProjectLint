import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct OnChangeOldAPIVisitorTests {

    private func makeVisitor() -> OnChangeOldAPIVisitor {
        let pattern = OnChangeOldAPIPatternRegistrar().pattern
        return OnChangeOldAPIVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: OnChangeOldAPIVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsSingleParameterOnChange() throws {
        let source = """
        Text("Hello")
            .onChange(of: value) { newValue in
                doSomething(newValue)
            }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .onChangeOldAPI)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("onChange"))
    }

    @Test
    func testDetectsSingleParameterOnChangeWithShortName() throws {
        let source = """
        Text("Count")
            .onChange(of: count) { val in
                print(val)
            }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func testDetectsMultipleOldOnChange() throws {
        let source = """
        Text("Hello")
            .onChange(of: value) { newValue in
                doSomething(newValue)
            }
            .onChange(of: count) { newCount in
                handle(newCount)
            }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForZeroParameterOnChange() {
        let source = """
        Text("Hello")
            .onChange(of: value) {
                doSomething()
            }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForTwoParameterOnChange() {
        let source = """
        Text("Hello")
            .onChange(of: value) { old, new in
                handle(old, new)
            }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForOnAppear() {
        let source = """
        Text("Hello")
            .onAppear {
                loadData()
            }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForOtherModifiers() {
        let source = """
        Text("Hello")
            .onReceive(publisher) { value in
                handle(value)
            }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

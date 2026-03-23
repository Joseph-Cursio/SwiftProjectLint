import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct OnChangeOldAPIVisitorTests {

    private func makeVisitor() -> OnChangeOldAPIVisitor {
        let pattern = OnChangeOldAPI().pattern
        return OnChangeOldAPIVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: OnChangeOldAPIVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsSingleParameterOnChange() throws {
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
    func detectsSingleParameterOnChangeWithShortName() {
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
    func detectsMultipleOldOnChange() {
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

    @Test("No issue for non-legacy onChange usage", arguments: [
        // Zero-parameter onChange
        """
        Text("Hello")
            .onChange(of: value) {
                doSomething()
            }
        """,
        // Two-parameter onChange
        """
        Text("Hello")
            .onChange(of: value) { old, new in
                handle(old, new)
            }
        """,
        // onAppear (not onChange)
        """
        Text("Hello")
            .onAppear {
                loadData()
            }
        """,
        // Other modifiers
        """
        Text("Hello")
            .onReceive(publisher) { value in
                handle(value)
            }
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

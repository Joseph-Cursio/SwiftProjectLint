import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct PrintStatementVisitorTests {

    private func makeVisitor() -> PrintStatementVisitor {
        let pattern = PrintStatementPatternRegistrar().pattern
        return PrintStatementVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: PrintStatementVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsPrintCall() throws {
        let source = """
        print("hello")
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .printStatement)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("print()"))
    }

    @Test
    func testDetectsDebugPrintCall() throws {
        let source = """
        debugPrint(object)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func testDetectsPrintWithMultipleArguments() throws {
        let source = """
        print("x:", someValue)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func testDetectsMultiplePrintCalls() throws {
        let source = """
        print("start")
        debugPrint(data)
        print("end")
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 3)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForLoggerCall() {
        let source = """
        logger.info("hello")
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForMemberAccessPrint() {
        let source = """
        textField.print()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForOtherFunctions() {
        let source = """
        log("message")
        NSLog("something")
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

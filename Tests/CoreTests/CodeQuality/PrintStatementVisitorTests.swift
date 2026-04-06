import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct PrintStatementVisitorTests {

    private func makeVisitor() -> PrintStatementVisitor {
        let pattern = PrintStatement().pattern
        return PrintStatementVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: PrintStatementVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Property Validation

    @Test
    func detectsPrintCallWithFullProperties() throws {
        let source = """
        print("hello")
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .printStatement)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("print()"))
        #expect(issue.message.contains("production"))
    }

    // MARK: - Parameterized Positive Cases

    @Test("Detects print/debugPrint call", arguments: [
        "print(\"hello\")",
        "debugPrint(object)",
        "print(\"x:\", someValue)"
    ])
    func detectsPrintCall(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsMultiplePrintCalls() {
        let source = """
        print("start")
        debugPrint(data)
        print("end")
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 3)
    }

    @Test
    func debugPrintHasSpecificMessage() throws {
        let source = """
        debugPrint(object)
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("debugPrint()"))
        #expect(issue.message.contains("left over"))
    }

    // MARK: - Suppression: #if DEBUG

    @Test
    func suppressesPrintInsideIfDebug() {
        let source = """
        #if DEBUG
        print("debug only")
        debugPrint(data)
        #endif
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func stillFlagsPrintOutsideIfDebug() {
        let source = """
        #if DEBUG
        print("debug only")
        #endif
        print("production code")
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues.first?.message.contains("production") == true)
    }

    // MARK: - Parameterized Negative Cases

    @Test("No issue for non-print function calls", arguments: [
        "logger.info(\"hello\")",
        "textField.print()",
        "log(\"message\")\nNSLog(\"something\")"
    ])
    func noIssueForNonPrintCalls(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftParser

@Suite
struct DiscardableResultMisuseVisitorTests {

    private func makeVisitor() -> DiscardableResultMisuseVisitor {
        DiscardableResultMisuseVisitor(pattern: DiscardableResultMisuse().pattern)
    }

    private func run(_ visitor: DiscardableResultMisuseVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Detection: return type signals

    @Test
    func detectsResultReturnType() throws {
        let source = """
        @discardableResult
        func save() throws -> Result<Void, Error> { .success(()) }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .discardableResultMisuse)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("save"))
    }

    @Test("Detects meaningful return type suffixes", arguments: [
        ("@discardableResult\nfunc validate() -> ValidationResult { .success }", "ValidationResult"),
        ("@discardableResult\nfunc submit() -> SubmitResponse { SubmitResponse() }", "SubmitResponse"),
        ("@discardableResult\nfunc getStatus() -> AuthStatus { .active }", "AuthStatus"),
        ("@discardableResult\nfunc evaluate() -> EvalOutcome { .pass }", "EvalOutcome")
    ])
    func detectsMeaningfulSuffix(source: String, returnType: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("Detects suspicious function names", arguments: [
        "@discardableResult\nfunc validateInput(_ s: String) -> Bool { !s.isEmpty }",
        "@discardableResult\nfunc authenticateUser() -> Bool { true }",
        "@discardableResult\nfunc saveRecord() -> Bool { true }",
        "@discardableResult\nfunc submitForm() -> String { \"ok\" }",
        "@discardableResult\nfunc deleteRecord() -> Int { 1 }"
    ])
    func detectsSuspiciousName(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - No issues

    @Test("No issue for legitimate @discardableResult uses", arguments: [
        // Append/builder style — chaining optional
        "@discardableResult\nfunc appending(_ element: Int) -> Self { self }",
        "@discardableResult\nfunc withFont(_ font: Font) -> Self { self }",
        // No @discardableResult
        "func save() -> Result<Void, Error> { .success(()) }",
        "func validate() -> Bool { true }",
        // @discardableResult with no return clause
        "@discardableResult\nfunc fire() {}"
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func noIssueForBuilderMethod() {
        let source = """
        @discardableResult
        func font(_ font: Font) -> Text { self }
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        // "font" is not a suspicious name and "Text" has no meaningful suffix
        #expect(visitor.detectedIssues.isEmpty)
    }
}

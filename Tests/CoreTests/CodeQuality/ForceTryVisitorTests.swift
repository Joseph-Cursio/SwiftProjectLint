import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct ForceTryVisitorTests {

    private func makeVisitor() -> ForceTryVisitor {
        let pattern = ForceTry().pattern
        return ForceTryVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ForceTryVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Property Validation

    @Test
    func detectsForceTryWithFullProperties() throws {
        let source = """
        let result = try! JSONDecoder().decode(Model.self, from: data)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .forceTry)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("try!"))
    }

    // MARK: - Parameterized Positive Cases

    @Test("Detects force try expression", arguments: [
        "let result = try! JSONDecoder().decode(Model.self, from: data)",
        "let value = try! someFunc()"
    ])
    func detectsForceTry(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsMultipleForceTries() {
        let source = """
        let first = try! loadData()
        let second = try! parseJSON()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Parameterized Negative Cases

    @Test("No issue for safe try usage", arguments: [
        "let result = try someFunc()",
        "let result = try? someFunc()",
        "do {\n    let result = try someFunc()\n} catch {\n    print(error)\n}"
    ])
    func noIssueForSafeTry(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

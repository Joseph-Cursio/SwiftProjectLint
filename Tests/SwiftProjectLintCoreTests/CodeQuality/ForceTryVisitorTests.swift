import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct ForceTryVisitorTests {

    private func makeVisitor() -> ForceTryVisitor {
        let pattern = ForceTryPatternRegistrar().pattern
        return ForceTryVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ForceTryVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsForceTryDecode() throws {
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

    @Test
    func testDetectsForceTryFunctionCall() throws {
        let source = """
        let value = try! someFunc()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func testDetectsMultipleForceTries() throws {
        let source = """
        let first = try! loadData()
        let second = try! parseJSON()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 2)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForRegularTry() {
        let source = """
        let result = try someFunc()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForOptionalTry() {
        let source = """
        let result = try? someFunc()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForDoCatch() {
        let source = """
        do {
            let result = try someFunc()
        } catch {
            print(error)
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

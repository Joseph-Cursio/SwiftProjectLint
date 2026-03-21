import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct NonisolatedUnsafeVisitorTests {

    private func makeVisitor() -> NonisolatedUnsafeVisitor {
        let pattern = NonisolatedUnsafePatternRegistrar().pattern
        return NonisolatedUnsafeVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: NonisolatedUnsafeVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsNonisolatedUnsafeVar() throws {
        let source = """
        nonisolated(unsafe) var detectorOverride: Foo?
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .nonisolatedUnsafe)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("nonisolated(unsafe)"))
    }

    @Test
    func testDetectsNonisolatedUnsafePrivateVar() throws {
        let source = """
        nonisolated(unsafe) private var cache: [String]
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .nonisolatedUnsafe)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForNonisolatedWithoutUnsafe() {
        let source = """
        nonisolated var value: Int { 42 }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForPlainVariable() {
        let source = """
        private var normal: Int = 0
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForMainActorVar() {
        let source = """
        @MainActor var value = 0
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

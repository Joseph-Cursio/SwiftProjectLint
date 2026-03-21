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

    // MARK: - Detailed Positive Case

    @Test
    func detectsNonisolatedUnsafeVar() throws {
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

    @Test("Detects nonisolated(unsafe) variant", arguments: [
        """
        nonisolated(unsafe) private var cache: [String]
        """
    ])
    func detectsVariant(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test("No issue for safe isolation patterns", arguments: [
        // nonisolated without unsafe
        """
        nonisolated var value: Int { 42 }
        """,
        // Plain variable
        """
        private var normal: Int = 0
        """,
        // MainActor var
        """
        @MainActor var value = 0
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

import Testing
@testable import Core
import SwiftSyntax
import SwiftParser

@Suite
struct SwallowedTaskErrorVisitorTests {

    private func makeVisitor() -> SwallowedTaskErrorVisitor {
        let pattern = SwallowedTaskError().pattern
        return SwallowedTaskErrorVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: SwallowedTaskErrorVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Positive Case

    @Test
    func detectsTaskWithTryNoDocatch() throws {
        let source = """
        Task {
            try await riskyWork()
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .swallowedTaskError)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("try"))
    }

    // swiftprojectlint:disable Test Missing Require
    @Test("Detects swallowed error variant", arguments: [
        """
        Task {
            let data = try await fetch()
        }
        """
    ])
    func detectsVariant(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    // swiftprojectlint:disable Test Missing Require
    @Test("No issue for proper error handling", arguments: [
        // Task with do-catch
        """
        Task {
            do {
                try await riskyWork()
            } catch {
                print(error)
            }
        }
        """,
        // Task without try
        """
        Task {
            await nonThrowingWork()
        }
        """,
        // try outside Task
        """
        try await riskyWork()
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Task.value / Task.result Suppression

    // swiftprojectlint:disable Test Missing Require
    @Test("No issue when Task .value is awaited", arguments: [
        // try await Task { }.value
        """
        try await Task { @MainActor in
            try await riskyWork()
        }.value
        """,
        // let result = try await Task { }.value
        """
        let result = try await Task {
            try await fetch()
        }.value
        """,
        // Task { }.result
        """
        let result = await Task {
            try await fetch()
        }.result
        """
    ])
    func noIssueWhenValueConsumed(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test("No issue when Task is assigned to a variable")
    func noIssueWhenTaskAssigned() {
        let source = """
        let task = Task {
            try await riskyWork()
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test("Still flags fire-and-forget Task with try")
    func stillFlagsFireAndForget() {
        let source = """
        Task {
            try await riskyWork()
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }
}

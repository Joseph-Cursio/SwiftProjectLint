import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct NonisolatedUnsafeVisitorTests {

    private func makeVisitor() -> NonisolatedUnsafeVisitor {
        let pattern = NonisolatedUnsafe().pattern
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

    // MARK: - Lock suppression

    @Test("No issue when enclosing type has OSAllocatedUnfairLock")
    func suppressedByOSAllocatedUnfairLock() {
        let source = """
        final class Watcher {
            private let lock = OSAllocatedUnfairLock()
            private nonisolated(unsafe) var handler: (() -> Void)?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when enclosing type has generic OSAllocatedUnfairLock")
    func suppressedByGenericOSAllocatedUnfairLock() {
        let source = """
        final class Watcher {
            private let lock = OSAllocatedUnfairLock<()>()
            private nonisolated(unsafe) var handler: (() -> Void)?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when enclosing type has Mutex")
    func suppressedByMutex() {
        let source = """
        final class Cache {
            private let lock = Mutex<[String: Int]>([:])
            nonisolated(unsafe) var data: [String: Int] = [:]
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when enclosing type has NSLock")
    func suppressedByNSLock() {
        let source = """
        class Service {
            private let lock = NSLock()
            nonisolated(unsafe) var value: Int = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Issue still reported when no lock in enclosing type")
    func notSuppressedWithoutLock() {
        let source = """
        final class BadActor {
            nonisolated(unsafe) var state: Int = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("Issue still reported for top-level nonisolated(unsafe) var")
    func notSuppressedAtTopLevel() {
        let source = """
        nonisolated(unsafe) var globalState: Int = 0
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }
}

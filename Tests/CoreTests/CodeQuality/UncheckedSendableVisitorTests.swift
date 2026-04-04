import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct UncheckedSendableVisitorTests {

    private func makeVisitor() -> UncheckedSendableVisitor {
        let pattern = UncheckedSendable().pattern
        return UncheckedSendableVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: UncheckedSendableVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Flagged Cases

    @Test
    func detectsClassWithNoLock() throws {
        let source = """
        class NetworkCache: @unchecked Sendable {
            var cache: [String: Data] = [:]
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .uncheckedSendable)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("NetworkCache"))
        #expect(issue.message.contains("@unchecked Sendable"))
    }

    @Test
    func detectsStructWithNoLock() {
        let source = """
        struct Config: @unchecked Sendable {
            var value: String = ""
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test
    func detectsEnumWithNoLock() {
        let source = """
        enum State: @unchecked Sendable {
            case idle
            case running
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("Detects @unchecked Sendable with multiple conformances, no lock")
    func detectsWhenSendableIsAmongMultipleConformances() {
        let source = """
        class Service: Hashable, @unchecked Sendable {
            var state: Int = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("Message includes the type name")
    func messageContainsTypeName() throws {
        let source = """
        class MyCache: @unchecked Sendable {
            var data: [String: Int] = [:]
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("MyCache"))
    }

    // MARK: - Not Flagged (Plain Sendable)

    @Test("No issue for plain Sendable conformance without @unchecked")
    func noIssueForPlainSendable() {
        let source = """
        class Handler: Sendable {
            let value: Int = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for types with no Sendable conformance")
    func noIssueForNonSendableType() {
        let source = """
        class DataStore {
            var cache: [String: Data] = [:]
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Lock Suppression

    @Test("Suppressed when class has OSAllocatedUnfairLock")
    func suppressedByOSAllocatedUnfairLock() {
        let source = """
        final class ThreadSafeCache: @unchecked Sendable {
            private let lock = OSAllocatedUnfairLock()
            private var cache: [String: Data] = [:]
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Suppressed when class has generic OSAllocatedUnfairLock")
    func suppressedByGenericOSAllocatedUnfairLock() {
        let source = """
        final class Watcher: @unchecked Sendable {
            private let lock = OSAllocatedUnfairLock<()>()
            private var handler: (() -> Void)?
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Suppressed when class has Mutex")
    func suppressedByMutex() {
        let source = """
        final class Cache: @unchecked Sendable {
            private let lock = Mutex<[String: Int]>([:])
            private var data: [String: Int] = [:]
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Suppressed when class has NSLock")
    func suppressedByNSLock() {
        let source = """
        class Service: @unchecked Sendable {
            private let lock = NSLock()
            private var value: Int = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Suppressed when class has NSRecursiveLock")
    func suppressedByNSRecursiveLock() {
        let source = """
        class Service: @unchecked Sendable {
            private let lock = NSRecursiveLock()
            private var value: Int = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Suppressed when class has NSLock via explicit type annotation")
    func suppressedByExplicitTypeAnnotation() {
        let source = """
        class Service: @unchecked Sendable {
            private let lock: NSLock = NSLock()
            private var value: Int = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("Suppressed when struct has a lock")
    func suppressedStructWithLock() {
        let source = """
        struct Buffer: @unchecked Sendable {
            private let lock = NSLock()
            private var items: [Int] = []
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Multiple Types

    @Test("Only flags types without lock when multiple types in source")
    func onlyFlagsUnsafeType() {
        let source = """
        class Safe: @unchecked Sendable {
            private let lock = NSLock()
            private var data: Int = 0
        }

        class Unsafe: @unchecked Sendable {
            var data: Int = 0
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        #expect(visitor.detectedIssues[0].message.contains("Unsafe"))
    }
}

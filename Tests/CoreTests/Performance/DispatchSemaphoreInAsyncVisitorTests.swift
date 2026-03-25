import Testing
@testable import Core
import SwiftSyntax
import SwiftParser

@Suite
struct DispatchSemaphoreInAsyncVisitorTests {

    private func makeVisitor() -> DispatchSemaphoreInAsyncVisitor {
        let pattern = DispatchSemaphoreInAsync().pattern
        return DispatchSemaphoreInAsyncVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: DispatchSemaphoreInAsyncVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsSemaphoreInAsyncFunction() throws {
        let source = """
        import Foundation

        class DataLoader {
            func fetchData() async {
                let semaphore = DispatchSemaphore(value: 0)
                semaphore.wait()
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .dispatchSemaphoreInAsync)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("DispatchSemaphore"))
    }

    // swiftprojectlint:disable Test Missing Require
    @Test("Detects semaphore in async context", arguments: [
        // async throws function
        """
        import Foundation

        class NetworkService {
            func loadItems() async throws {
                let semaphore = DispatchSemaphore(value: 1)
                performLegacyCall()
                semaphore.wait()
            }
        }
        """,
        // async closure
        """
        import Foundation

        class Worker {
            func start() {
                let work = { @Sendable () async in
                    let semaphore = DispatchSemaphore(value: 0)
                    semaphore.wait()
                }
            }
        }
        """
    ])
    func detectsSemaphoreVariant(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    // swiftprojectlint:disable Test Missing Require
    @Test("No issue for semaphore in sync context", arguments: [
        // Sync function
        """
        import Foundation

        class LegacyService {
            func fetchData() {
                let semaphore = DispatchSemaphore(value: 0)
                URLSession.shared.dataTask(with: url) { _, _, _ in
                    semaphore.signal()
                }.resume()
                semaphore.wait()
            }
        }
        """,
        // Top-level
        """
        import Foundation

        let semaphore = DispatchSemaphore(value: 1)
        """,
        // Sync function nested beside async function
        """
        import Foundation

        class DataLoader {
            func fetchData() async {
                processSync()
            }

            func processSync() {
                let semaphore = DispatchSemaphore(value: 0)
                semaphore.wait()
            }
        }
        """,
        // Sync closure inside async function
        """
        import Foundation

        class DataLoader {
            func fetchData() async {
                let callback = {
                    let semaphore = DispatchSemaphore(value: 0)
                    semaphore.wait()
                }
            }
        }
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

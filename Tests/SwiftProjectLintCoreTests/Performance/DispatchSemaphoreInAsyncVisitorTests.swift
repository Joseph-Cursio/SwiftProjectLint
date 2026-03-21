import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct DispatchSemaphoreInAsyncVisitorTests {

    private func makeVisitor() -> DispatchSemaphoreInAsyncVisitor {
        let pattern = DispatchSemaphoreInAsyncPatternRegistrar().pattern
        return DispatchSemaphoreInAsyncVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: DispatchSemaphoreInAsyncVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsSemaphoreInAsyncFunction() throws {
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

    @Test
    func testDetectsSemaphoreInAsyncThrowsFunction() throws {
        let source = """
        import Foundation

        class NetworkService {
            func loadItems() async throws {
                let semaphore = DispatchSemaphore(value: 1)
                performLegacyCall()
                semaphore.wait()
            }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .dispatchSemaphoreInAsync)
    }

    @Test
    func testDetectsSemaphoreInAsyncClosure() throws {
        let source = """
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

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForSemaphoreInSyncFunction() {
        let source = """
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
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForSemaphoreAtTopLevel() {
        let source = """
        import Foundation

        let semaphore = DispatchSemaphore(value: 1)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForSyncFunctionNestedInsideAsyncFunction() {
        let source = """
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
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForSyncClosureInsideAsyncFunction() {
        let source = """
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

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

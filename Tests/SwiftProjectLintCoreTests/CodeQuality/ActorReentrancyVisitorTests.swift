import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct ActorReentrancyVisitorTests {

    private func makeVisitor() -> ActorReentrancyVisitor {
        let pattern = ActorReentrancyPatternRegistrar().pattern
        return ActorReentrancyVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: ActorReentrancyVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func detectsGuardWithoutUpdate() throws {
        let source = """
        actor InsightsEngine {
            var lastRunDate: Date?
            let minimumInterval: Duration = .seconds(60)

            func runIfDue() async throws -> [String] {
                if let lastRun = lastRunDate {
                    let elapsed = Duration.seconds(Date().timeIntervalSince(lastRun))
                    guard elapsed >= minimumInterval else { return [] }
                }
                return try await runAnalysis()
            }

            private func runAnalysis() async throws -> [String] { [] }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .actorReentrancy)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("lastRunDate"))
        #expect(issue.message.contains("runIfDue"))
    }

    @Test
    func detectsBooleanGuardWithoutUpdate() throws {
        let source = """
        actor DataLoader {
            var isLoading = false

            func fetchData() async throws -> Data {
                guard !isLoading else { return Data() }
                let result = try await performFetch()
                return result
            }

            private func performFetch() async throws -> Data { Data() }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .actorReentrancy)
        #expect(issue.message.contains("isLoading"))
    }

    @Test
    func detectsSelfDotPropertyReference() throws {
        let source = """
        actor Scheduler {
            var isRunning = false

            func execute() async throws {
                guard !self.isRunning else { return }
                try await performWork()
            }

            private func performWork() async throws {}
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("isRunning"))
    }

    @Test
    func detectsMultipleUncheckedProperties() {
        let source = """
        actor Processor {
            var isActive = false
            var lastProcessed: Date?

            func process() async throws {
                guard isActive else { return }
                if let last = lastProcessed {
                    guard Date().timeIntervalSince(last) > 5 else { return }
                }
                try await doWork()
            }

            private func doWork() async throws {}
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        // Should detect at least one reentrancy issue
        #expect(!visitor.detectedIssues.isEmpty)
    }

    // MARK: - Negative Cases

    @Test("No issue for valid actor code", arguments: [
        // Property set before await
        """
        actor DataLoader {
            var isLoading = false

            func fetchData() async throws -> Data {
                guard !isLoading else { return Data() }
                isLoading = true
                let result = try await performFetch()
                isLoading = false
                return result
            }

            private func performFetch() async throws -> Data { Data() }
        }
        """,
        // self.property set before await
        """
        actor Scheduler {
            var isRunning = false

            func execute() async throws {
                guard !isRunning else { return }
                self.isRunning = true
                try await performWork()
                self.isRunning = false
            }

            private func performWork() async throws {}
        }
        """,
        // Sync function (no async)
        """
        actor Counter {
            var count = 0

            func increment() {
                guard count < 100 else { return }
                count += 1
            }
        }
        """,
        // Async function without guard
        """
        actor Fetcher {
            var data: Data?

            func fetch() async throws -> Data {
                let result = try await performFetch()
                data = result
                return result
            }

            private func performFetch() async throws -> Data { Data() }
        }
        """,
        // Class instead of actor
        """
        class DataLoader {
            var isLoading = false

            func fetchData() async throws -> Data {
                guard !isLoading else { return Data() }
                let result = try await performFetch()
                return result
            }

            private func performFetch() async throws -> Data { Data() }
        }
        """,
        // Let properties (immutable)
        """
        actor Config {
            let threshold: Int = 10
            var data: [String] = []

            func process() async throws {
                guard threshold > 5 else { return }
                data = try await loadData()
            }

            private func loadData() async throws -> [String] { [] }
        }
        """,
        // Computed properties
        """
        actor Monitor {
            var readings: [Double] = []
            var average: Double {
                readings.reduce(0, +) / Double(readings.count)
            }

            func check() async throws {
                guard average > 0 else { return }
                try await recordReading()
            }

            private func recordReading() async throws {}
        }
        """,
        // Date set eagerly before await
        """
        actor InsightsEngine {
            var lastRunDate: Date?
            let minimumInterval: Duration = .seconds(60)

            func runIfDue() async throws -> [String] {
                if let lastRun = lastRunDate {
                    let elapsed = Duration.seconds(Date.now.timeIntervalSince(lastRun))
                    guard elapsed >= minimumInterval else { return [] }
                }
                lastRunDate = .now
                return try await runAnalysis()
            }

            private func runAnalysis() async throws -> [String] { [] }
        }
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}

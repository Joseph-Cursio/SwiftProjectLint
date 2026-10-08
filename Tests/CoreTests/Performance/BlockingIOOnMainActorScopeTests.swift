@testable import Core
import Testing

/// Code that does not run on the main actor, and blocking calls other rules already report.
@Suite
struct BlockingIOOnMainActorScopeTests {

    // MARK: - Not on the main actor

    @Test("Code with no main-actor isolation is not flagged", arguments: [
        // A plain type: nothing says where it runs.
        """
        final class ReceiptStore {
            func load(url: URL) -> Data? { try? Data(contentsOf: url) }
        }
        """,
        // An actor has its own executor.
        """
        actor ReceiptStore {
            func load(url: URL) -> Data? { try? Data(contentsOf: url) }
        }
        """,
        // Another global actor.
        """
        @DatabaseActor final class ReceiptStore {
            func load(url: URL) -> Data? { try? Data(contentsOf: url) }
        }
        """,
        // A free function.
        """
        func load(url: URL) -> Data? { try? Data(contentsOf: url) }
        """
    ])
    func unisolatedCodeIsNotFlagged(source: String) {
        #expect(BlockingIOHarness.issues(source).isEmpty)
    }

    @Test("Opting a member out of the main actor is honoured", arguments: [
        """
        @MainActor final class Loader {
            nonisolated func load(url: URL) -> Data? { try? Data(contentsOf: url) }
        }
        """,
        """
        @MainActor final class Loader {
            @concurrent func load(url: URL) async -> Data? { try? Data(contentsOf: url) }
        }
        """,
        """
        @MainActor final class Loader {
            deinit { _ = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/x")) }
        }
        """
    ])
    func memberOptOutIsHonoured(source: String) {
        #expect(BlockingIOHarness.issues(source).isEmpty)
    }

    @Test
    func nestedTypeDoesNotInheritOuterIsolation() {
        let issues = BlockingIOHarness.issues("""
        @MainActor final class Library {
            struct Parser {
                func parse(path: String) -> String? { try? String(contentsOfFile: path, encoding: .utf8) }
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    @Test("Closures handed off the main actor are not flagged", arguments: [
        "Task.detached { _ = try? Data(contentsOf: url) }",
        "DispatchQueue.global(qos: .utility).async { _ = try? Data(contentsOf: url) }",
        "Thread.detachNewThread { _ = try? Data(contentsOf: url) }",
        "let work = { @Sendable in _ = try? Data(contentsOf: url) }",
        "URLSession.shared.dataTask(with: url) { data, _, _ in try? data?.write(to: url) }.resume()",
        """
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { _ = try? Data(contentsOf: url) }
            }
        }
        """
    ])
    func handOffClosuresAreNotFlagged(body: String) {
        let issues = BlockingIOHarness.issues("""
        @MainActor final class Loader {
            func start(url: URL) {
                \(body)
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    @Test
    func awaitedCallIsNotBlocking() {
        let issues = BlockingIOHarness.issues("""
        @MainActor final class Loader {
            let files: FileStore
            func load() async throws -> Data? {
                try await files.contents(atPath: "/tmp/x")
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    @Test("An unisolated model's async work leaves the main actor", arguments: [
        """
        @Observable final class FeedModel {
            func refresh(url: URL) async { _ = try? Data(contentsOf: url) }
        }
        """,
        """
        @Observable final class FeedModel {
            func refresh(url: URL) {
                Task { _ = try? Data(contentsOf: url) }
            }
        }
        """
    ])
    func modelAsyncWorkIsNotFlagged(source: String) {
        #expect(BlockingIOHarness.issues(source).isEmpty)
    }

    @Test
    func testAndFixtureFilesAreExempt() {
        let source = """
        @MainActor final class LoaderTests {
            func testLoad() { _ = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/x")) }
        }
        """

        #expect(BlockingIOHarness.issues(source, paths: ["Tests/AppTests/LoaderTests.swift"]).isEmpty)
    }

    // MARK: - Left to the rule that already reports it

    @Test("Blocking calls another rule reports are not reported twice", arguments: [
        // `Synchronous Network Call`
        "_ = try? Data(contentsOf: URL(string: \"https://example.com/feed\")!)",
        // `Thread Sleep`
        "Thread.sleep(forTimeInterval: 1)",
        // `Dispatch Semaphore in Async` — creation and wait in one async scope
        """
        let semaphore = DispatchSemaphore(value: 0)
        legacyFetch { semaphore.signal() }
        semaphore.wait()
        """
    ])
    func callsOwnedByAnotherRuleAreSkipped(body: String) {
        let issues = BlockingIOHarness.issues("""
        @MainActor final class Loader {
            func start() async {
                \(body)
            }
        }
        """)

        #expect(issues.isEmpty)
    }

    @Test
    func semaphoreWaitInSynchronousMainActorCodeIsFlagged() {
        // `Dispatch Semaphore in Async` only reports async scopes, so this one is ours.
        let issues = BlockingIOHarness.issues("""
        @MainActor final class Loader {
            func startSync() {
                let semaphore = DispatchSemaphore(value: 0)
                legacyFetch { semaphore.signal() }
                semaphore.wait()
            }
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'wait()'") == true)
    }

    @Test
    func unrelatedCallsAreNotFlagged() {
        let issues = BlockingIOHarness.issues("""
        import SwiftUI
        struct ContentView: View {
            @State private var items: [String] = []
            var body: some View {
                List(items, id: \\.self) { Text($0) }
                    .task { items = try! JSONDecoder().decode([String].self, from: Data()) }
            }
            func write(_ text: String) { print(text) }
            func save() { write("done") }
        }
        """)

        #expect(issues.isEmpty)
    }
}

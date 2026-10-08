@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Drives `BlockingIOOnMainActorVisitor` the way the cross-file engine does: walk every file,
/// then finalize once.
enum BlockingIOHarness {
    static func issues(_ sources: String..., paths: [String] = []) -> [LintIssue] {
        let visitor = BlockingIOOnMainActorVisitor(pattern: BlockingIOOnMainActor().pattern)
        for (index, source) in sources.enumerated() {
            let path = index < paths.count ? paths[index] : "Sources/App/File\(index).swift"
            let tree = Parser.parse(source: source)
            visitor.setFilePath(path)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: path, tree: tree))
            visitor.walk(tree)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues
    }
}

@Suite
struct BlockingIOOnMainActorVisitorTests {

    // MARK: - The reproduction

    @Test
    func flagsDataContentsOfInMainActorObservableViewModel() throws {
        let issues = BlockingIOHarness.issues("""
        import Foundation
        import Observation

        @MainActor
        @Observable
        final class ReceiptViewModel {
            var text = ""
            let receiptURL: URL
            init(receiptURL: URL) { self.receiptURL = receiptURL }
            func loadReceipt() {
                if let data = try? Data(contentsOf: receiptURL) {
                    text = String(decoding: data, as: UTF8.self)
                }
            }
        }
        """)

        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.ruleName == .blockingIOOnMainActor)
        #expect(issue.severity == .warning)
        #expect(issue.lineNumber == 11)
        #expect(issue.message.contains("'Data(contentsOf:)' loads its URL synchronously on the main actor"))
        #expect(issue.message.contains("'ReceiptViewModel' is @MainActor"))
        #expect(issue.suggestion?.contains("Task { } does not help") == true)
    }

    // MARK: - Where the main actor comes from

    @Test
    func flagsSynchronousMethodOfUnannotatedObservableModel() throws {
        let issues = BlockingIOHarness.issues("""
        @Observable
        final class NotesModel {
            func load(from path: String) -> String {
                (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            }
        }
        """)

        let issue = try #require(issues.first)
        #expect(issue.message.contains("'String(contentsOfFile:encoding:)'"))
        #expect(issue.message.contains("'NotesModel' is an @Observable model"))
    }

    @Test
    func flagsSynchronousMethodOfObservableObject() {
        let issues = BlockingIOHarness.issues("""
        final class SettingsStore: ObservableObject {
            @Published var names: [String] = []
            func refresh(directory: String) {
                names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            }
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'SettingsStore' is an ObservableObject model") == true)
        #expect(issues.first?.message.contains("does synchronous file-system work") == true)
    }

    @Test
    func flagsViewBodyAndButtonAction() {
        let issues = BlockingIOHarness.issues("""
        import SwiftUI

        struct LicenseView: View {
            let url: URL
            var body: some View {
                Text((try? String(contentsOf: url, encoding: .utf8)) ?? "")
                Button("Reload") {
                    _ = try? Data(contentsOf: url)
                }
            }
        }
        """)

        #expect(issues.count == 2)
        #expect(issues.allSatisfy { $0.message.contains("'LicenseView' conforms to View, which is @MainActor") })
    }

    @Test
    func flagsMainActorFunctionInUnannotatedType() {
        let issues = BlockingIOHarness.issues("""
        final class Exporter {
            @MainActor func save(_ data: Data, to url: URL) throws {
                try data.write(to: url)
            }
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'write(to:)' writes a file synchronously") == true)
        #expect(issues.first?.message.contains("'save()' is @MainActor") == true)
    }

    @Test
    func flagsUIKitSubclass() {
        let issues = BlockingIOHarness.issues("""
        import UIKit

        final class ReceiptViewController: UIViewController {
            override func viewDidLoad() {
                super.viewDidLoad()
                _ = FileManager.default.contents(atPath: "/tmp/receipt")
            }
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("inherits @MainActor from UIViewController") == true)
    }

    @Test
    func flagsConformanceToProjectMainActorProtocol() {
        let issues = BlockingIOHarness.issues("""
        @MainActor protocol Coordinator {}

        final class AppCoordinator: Coordinator {
            func start() { usleep(500_000) }
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'usleep(_:)' puts the main actor's thread to sleep") == true)
        #expect(issues.first?.message.contains("conforms to 'Coordinator', which is @MainActor") == true)
    }

    // MARK: - Across files

    @Test
    func flagsExtensionOfViewDeclaredInAnotherFile() {
        let issues = BlockingIOHarness.issues(
            """
            import SwiftUI
            struct ProfileView: View {
                var body: some View { Text("Profile") }
            }
            """,
            """
            import Foundation
            extension ProfileView {
                func avatar(at path: String) -> Data? {
                    FileManager.default.contents(atPath: path)
                }
            }
            """
        )

        #expect(issues.count == 1)
        #expect(issues.first?.filePath == "Sources/App/File1.swift")
        #expect(issues.first?.lineNumber == 4)
    }

    @Test
    func flagsSubclassOfProjectBaseControllerInAnotherFile() {
        let issues = BlockingIOHarness.issues(
            "import UIKit\nclass BaseViewController: UIViewController {}",
            """
            final class ImportViewController: BaseViewController {
                func importFile(_ handle: FileHandle) -> Data? {
                    try? handle.readToEnd()
                }
            }
            """
        )

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("inherits @MainActor from 'BaseViewController'") == true)
    }

    // MARK: - Async and hand-offs that stay on the main actor

    @Test
    func flagsMainActorAsyncFunction() {
        let issues = BlockingIOHarness.issues("""
        @MainActor final class Loader {
            func load(url: URL) async -> Data? {
                try? Data(contentsOf: url)
            }
        }
        """)

        #expect(issues.count == 1)
    }

    @Test
    func flagsTaskInheritingTheMainActor() {
        let issues = BlockingIOHarness.issues("""
        @MainActor final class Loader {
            func start(url: URL) {
                Task {
                    _ = try? Data(contentsOf: url)
                }
            }
        }
        """)

        #expect(issues.count == 1)
    }

    @Test
    func flagsMainActorHandOffsFromUnisolatedCode() {
        let issues = BlockingIOHarness.issues("""
        final class Worker {
            func finish(url: URL) async {
                await MainActor.run { _ = try? Data(contentsOf: url) }
                DispatchQueue.main.async { _ = try? Data(contentsOf: url) }
            }
        }
        """)

        #expect(issues.count == 2)
        #expect(issues.contains { $0.message.contains("it runs inside MainActor.run") })
        #expect(issues.contains { $0.message.contains("it runs on DispatchQueue.main") })
    }

    @Test
    func flagsMainActorClosure() {
        let issues = BlockingIOHarness.issues("""
        func schedule(url: URL) {
            Task { @MainActor in
                _ = try? Data(contentsOf: url)
            }
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("the closure is @MainActor") == true)
    }

    // MARK: - The catalog

    @Test
    func flagsWaitsAndProcessWaits() {
        let issues = BlockingIOHarness.issues("""
        @MainActor func runTool(_ process: Process, group: DispatchGroup) {
            process.waitUntilExit()
            group.wait()
            _ = group.wait(timeout: .now() + 1)
        }
        """)

        #expect(issues.count == 3)
        #expect(issues.allSatisfy { $0.message.contains("blocks the main actor until another thread signals it") })
        #expect(issues.allSatisfy { $0.suggestion?.contains("withCheckedContinuation") == true })
    }

    @Test
    func classifiesRemoteStringContentsAsNetwork() {
        let issues = BlockingIOHarness.issues("""
        @MainActor func fetchMotd() -> String? {
            try? String(contentsOf: URL(string: "https://example.com/motd")!, encoding: .utf8)
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("makes a synchronous network request") == true)
    }

    @Test
    func flagsExplicitInitSpellingOfRemoteData() {
        // `Synchronous Network Call` matches only `Data(contentsOf:)`, so this one is ours.
        let issues = BlockingIOHarness.issues("""
        @MainActor func fetch() -> Data? {
            try? Data.init(contentsOf: URL(string: "https://example.com")!)
        }
        """)

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'Data(contentsOf:)' makes a synchronous network request") == true)
    }
}

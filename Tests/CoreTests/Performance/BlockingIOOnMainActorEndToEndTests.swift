@testable import Core
import Foundation
import Testing

/// Through `ProjectLinter`, with every default rule on: the reproduction is reported as a
/// responsiveness problem, and a blocking call another rule owns is reported once, not twice.
@Suite
struct BlockingIOOnMainActorEndToEndTests {

    /// The rules that report blocking calls. On any one line, at most one of them should fire.
    private static let blockingRules: Set<RuleIdentifier> = [
        .blockingIOOnMainActor, .synchronousNetworkCall, .threadSleep, .dispatchSemaphoreInAsync
    ]

    @Test
    func reproductionIsReportedAsBlockingTheMainActor() async {
        let root = makePackage(files: [
            "Sources/App/ReceiptViewModel.swift": """
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
        """
        ])

        let issues = await analyze(root)
        let onCall = issues.filter { $0.lineNumber == 11 }

        #expect(onCall.contains { $0.ruleName == .blockingIOOnMainActor && $0.severity == .warning })
        #expect(onCall.filter { Self.blockingRules.contains($0.ruleName) }.count == 1)
    }

    @Test
    func eachBlockingCallOnTheMainActorIsReportedOnce() async {
        let root = makePackage(files: [
            "Sources/App/SyncView.swift": """
        import SwiftUI

        struct SyncView: View {
            var body: some View { Text("Sync") }

            func pause() {
                Thread.sleep(forTimeInterval: 1)
            }

            func fetch() -> Data? {
                try? Data(contentsOf: URL(string: "https://example.com/feed")!)
            }

            func wait() async {
                let semaphore = DispatchSemaphore(value: 0)
                semaphore.wait()
            }

            func readLocal(at fileURL: URL) -> Data? {
                try? Data(contentsOf: fileURL)
            }
        }
        """
        ])

        let issues = await analyze(root).filter { Self.blockingRules.contains($0.ruleName) }
        let byLine = Dictionary(grouping: issues, by: \.lineNumber)

        #expect(byLine[7]?.map(\.ruleName) == [.threadSleep])
        #expect(byLine[11]?.map(\.ruleName) == [.synchronousNetworkCall])
        #expect(byLine[15]?.map(\.ruleName) == [.dispatchSemaphoreInAsync])
        #expect(byLine[16] == nil)
        #expect(byLine[20]?.map(\.ruleName) == [.blockingIOOnMainActor])
    }

    // MARK: - Helpers

    private func analyze(_ root: String) async -> [LintIssue] {
        let system = PatternRegistryFactory.createConfiguredSystem()
        return await ProjectLinter().analyzeProject(at: root, detector: system.detector)
    }

    private func makePackage(files: [String: String]) -> String {
        let root = (FileManager.default.temporaryDirectory.path as NSString)
            .appendingPathComponent("BlockingIO-\(UUID().uuidString)")
        writeFile(at: "\(root)/Package.swift", "// swift-tools-version:6.0\n")
        for (path, content) in files {
            writeFile(at: "\(root)/\(path)", content)
        }
        return root
    }

    private func writeFile(at path: String, _ content: String) {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

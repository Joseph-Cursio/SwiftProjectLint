@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A target built with default MainActor isolation runs its unannotated code on the main actor,
/// though nothing in the file says so. The build setting reaches the rule as
/// `defaultMainActorSourcePaths`.
@Suite
struct BlockingIOOnMainActorDefaultIsolationTests {

    private static let helper = """
    import Foundation

    struct ReceiptLoader {
        func load(from url: URL) -> Data? {
            try? Data(contentsOf: url)
        }
    }

    func readConfig(at path: String) -> String? {
        try? String(contentsOfFile: path, encoding: .utf8)
    }
    """

    private func issues(_ files: [String: String], defaultPaths: [String]) -> [LintIssue] {
        let visitor = BlockingIOOnMainActorVisitor(pattern: BlockingIOOnMainActor().pattern)
        visitor.defaultMainActorSourcePaths = defaultPaths
        for path in files.keys.sorted() {
            let tree = Parser.parse(source: files[path] ?? "")
            visitor.setFilePath(path)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: path, tree: tree))
            visitor.walk(tree)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues
    }

    @Test
    func unannotatedCodeInADefaultMainActorTargetIsFlagged() {
        let found = issues(["Sources/App/ReceiptLoader.swift": Self.helper], defaultPaths: ["Sources/App/"])

        #expect(found.count == 2)
        #expect(found.contains { $0.message.contains("'ReceiptLoader' is in a target that defaults to MainActor") })
        #expect(found.contains { $0.message.contains("its target defaults to MainActor isolation") })
    }

    @Test
    func sameCodeOutsideTheTargetIsNotFlagged() {
        let found = issues(["Sources/Core/ReceiptLoader.swift": Self.helper], defaultPaths: ["Sources/App/"])

        #expect(found.isEmpty)
    }

    @Test
    func anExactFilePathCoversOnlyThatFile() {
        let found = issues(
            [
                "Sources/App/ReceiptLoader.swift": Self.helper,
                "Sources/App/Other.swift": Self.helper
            ],
            defaultPaths: ["Sources/App/ReceiptLoader.swift"]
        )

        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.filePath == "Sources/App/ReceiptLoader.swift" })
    }

    @Test("Opting out of the default is honoured", arguments: [
        "nonisolated struct Loader { func load(url: URL) -> Data? { try? Data(contentsOf: url) } }",
        "struct Loader { nonisolated func load(url: URL) -> Data? { try? Data(contentsOf: url) } }",
        "struct Loader { @concurrent func load(url: URL) async -> Data? { try? Data(contentsOf: url) } }",
        "actor Loader { func load(url: URL) -> Data? { try? Data(contentsOf: url) } }"
    ])
    func optOutIsHonoured(source: String) {
        #expect(issues(["Sources/App/Loader.swift": source], defaultPaths: ["Sources/App/"]).isEmpty)
    }

    @Test
    func extensionElsewhereSeesTheTypesDefault() {
        let found = issues(
            [
                "Sources/App/ReceiptLoader.swift": "struct ReceiptLoader {}",
                "Sources/Shared/ReceiptLoader+IO.swift": """
                extension ReceiptLoader {
                    func load(url: URL) -> Data? { try? Data(contentsOf: url) }
                }
                """
            ],
            defaultPaths: ["Sources/App/"]
        )

        #expect(found.count == 1)
        #expect(found.first?.filePath == "Sources/Shared/ReceiptLoader+IO.swift")
    }

    @Test
    func defaultIsolationOutranksTheModelRole() {
        // In a MainActor-default target a model is isolated, so its async methods run there too.
        let model = """
        @Observable final class FeedModel {
            func refresh(url: URL) async { _ = try? Data(contentsOf: url) }
        }
        """
        let found = issues(["Sources/App/FeedModel.swift": model], defaultPaths: ["Sources/App/"])

        #expect(found.count == 1)
    }
}

/// End to end: the setting is read from the manifest and reaches the rule.
@Suite
struct BlockingIOOnMainActorDefaultIsolationEndToEndTests {

    @Test
    func targetWithDefaultIsolationInItsManifestIsAnalysedAsMainActor() async {
        let root = (FileManager.default.temporaryDirectory.path as NSString)
            .appendingPathComponent("BlockingIODefault-\(UUID().uuidString)")
        write("""
        // swift-tools-version:6.2
        import PackageDescription

        let uiSettings: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

        let package = Package(
            name: "Demo",
            targets: [
                .target(name: "Core"),
                .executableTarget(name: "App", dependencies: ["Core"], swiftSettings: uiSettings)
            ]
        )
        """, to: "\(root)/Package.swift")
        let loader = """
        import Foundation

        struct Loader {
            func load(url: URL) -> Data? { try? Data(contentsOf: url) }
        }
        """
        write(loader, to: "\(root)/Sources/App/Loader.swift")
        write(loader, to: "\(root)/Sources/Core/Loader.swift")
        defer { try? FileManager.default.removeItem(atPath: root) }

        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await ProjectLinter().analyzeProject(at: root, detector: system.detector)
        let blocking = issues.filter { $0.ruleName == .blockingIOOnMainActor }

        #expect(blocking.map(\.filePath) == ["Sources/App/Loader.swift"])
    }

    private func write(_ content: String, to path: String) {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

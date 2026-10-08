@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// In a target built with default MainActor isolation (SE-0466) an unannotated class already is
/// `@MainActor`, so neither missing-`@MainActor` rule has anything to report there. The build
/// setting reaches both through `MainActorMissingVisitorBase` as `defaultMainActorSourcePaths`.
@Suite
struct MainActorMissingDefaultIsolationTests {

    /// The two rules built on `MainActorMissingVisitorBase`.
    enum Rule: CaseIterable {
        case mainActorMissing
        case observableMainActorMissing

        func makeVisitor() -> MainActorMissingVisitorBase {
            switch self {
            case .mainActorMissing:
                return MainActorMissingVisitor(pattern: MainActorMissing().pattern)

            case .observableMainActorMissing:
                return ObservableMainActorMissingVisitor(pattern: ObservableMainActorMissing().pattern)
            }
        }

        /// A class the rule reports when nothing makes it `@MainActor`, declared with `modifiers`.
        func model(modifiers: String = "") -> String {
            switch self {
            case .mainActorMissing:
                return """
                \(modifiers)class Model: ObservableObject {
                    @Published var count = 0
                }
                """

            case .observableMainActorMissing:
                return """
                @Observable
                \(modifiers)class Model {
                    var count = 0
                }
                """
            }
        }
    }

    private func issues(_ rule: Rule, _ files: [String: String], defaultPaths: [String]) -> [LintIssue] {
        let visitor = rule.makeVisitor()
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

    @Test(arguments: Rule.allCases)
    func classInADefaultMainActorTargetIsNotReported(rule: Rule) {
        let found = issues(
            rule,
            [
                "Sources/App/Model.swift": rule.model(),
                "Sources/Core/Model.swift": rule.model()
            ],
            defaultPaths: ["Sources/App/"]
        )

        #expect(found.map(\.filePath) == ["Sources/Core/Model.swift"])
    }

    @Test(arguments: Rule.allCases)
    func nonisolatedClassOptsOutOfTheDefault(rule: Rule) {
        let found = issues(
            rule,
            ["Sources/App/Model.swift": rule.model(modifiers: "nonisolated ")],
            defaultPaths: ["Sources/App/"]
        )

        #expect(found.map(\.filePath) == ["Sources/App/Model.swift"])
    }
}

/// End to end: the setting is read from the manifest and reaches both rules.
@Suite
struct MainActorMissingDefaultIsolationEndToEndTests {

    @Test
    func modelsInATargetWithDefaultIsolationInItsManifestAreNotReported() async {
        let root = (FileManager.default.temporaryDirectory.path as NSString)
            .appendingPathComponent("MainActorMissingDefault-\(UUID().uuidString)")
        write("""
        // swift-tools-version:6.2
        import PackageDescription

        let package = Package(
            name: "Demo",
            targets: [
                .target(name: "Core"),
                .executableTarget(
                    name: "App",
                    dependencies: ["Core"],
                    swiftSettings: [.defaultIsolation(MainActor.self)]
                )
            ]
        )
        """, to: "\(root)/Package.swift")
        let models = """
        import Combine
        import Observation

        class CounterViewModel: ObservableObject {
            @Published var count = 0
        }

        @Observable
        class CounterModel {
            var count = 0
        }
        """
        write(models, to: "\(root)/Sources/App/Models.swift")
        write(models, to: "\(root)/Sources/Core/Models.swift")
        defer { try? FileManager.default.removeItem(atPath: root) }

        let system = PatternRegistryFactory.createConfiguredSystem()
        let issues = await ProjectLinter().analyzeProject(at: root, detector: system.detector)
        let reported = issues
            .filter { [.mainActorMissingOnUICode, .observableMainActorMissing].contains($0.ruleName) }
            .map { "\($0.ruleName.rawValue) @ \($0.filePath)" }
            .sorted()

        #expect(reported == [
            "Main Actor Missing On UI Code @ Sources/Core/Models.swift",
            "Observable Main Actor Missing @ Sources/Core/Models.swift"
        ])
    }

    private func write(_ content: String, to path: String) {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

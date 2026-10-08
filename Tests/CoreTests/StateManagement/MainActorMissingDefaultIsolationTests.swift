@testable import Core
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

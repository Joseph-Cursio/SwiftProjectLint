@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Unused Target Dependency for products of local `.package(path:)` dependencies.
@Suite
struct UnusedProductDependencyTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        let cache = files.mapValues { Parser.parse(source: $0) }
        let visitor = UnusedTargetDependencyVisitor(fileCache: cache)
        visitor.setPattern(UnusedTargetDependency().pattern)
        for (name, ast) in cache.sorted(by: { $0.key < $1.key }) {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .unusedTargetDependency }
    }

    private let kitManifest = """
    let package = Package(
        name: "Kit",
        products: [
            .library(name: "KitUI", targets: ["KitUI"]),
            .library(name: "KitAll", targets: ["KitCore", "KitUI"])
        ],
        targets: [.target(name: "KitCore"), .target(name: "KitUI", dependencies: ["KitCore"])]
    )
    """

    private func workspace(app dependencies: String, appSource: String) -> [String: String] {
        [
            "Package.swift": """
            let package = Package(
                name: "App",
                dependencies: [.package(path: "Packages/Kit")],
                targets: [
                    .target(
                        name: "App",
                        dependencies: [
                            \(dependencies)
                        ]
                    )
                ]
            )
            """,
            "Sources/App/App.swift": appSource,
            "Packages/Kit/Package.swift": kitManifest,
            "Packages/Kit/Sources/KitCore/Core.swift": "struct Core {}",
            "Packages/Kit/Sources/KitUI/View.swift": "import KitCore"
        ]
    }

    // MARK: - Positive

    @Test func flagsAProductNoFileImports() throws {
        let issues = analyze(files: workspace(
            app: #".product(name: "KitUI", package: "kit")"#,
            appSource: "import Foundation"
        ))

        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.filePath == "Package.swift")
        #expect(issue.lineNumber == 8)
        #expect(issue.message == "Target 'App' declares a dependency on product 'KitUI' of 'kit' but never imports it")
        #expect(issue.suggestion?.hasPrefix(#"Remove .product(name: "KitUI", package: "kit")"#) == true)
    }

    @Test func flagsAProductNamedByAPlainString() throws {
        let issues = analyze(files: workspace(app: #""KitUI""#, appSource: "import Foundation"))

        let issue = try #require(issues.first)
        #expect(issue.suggestion?.hasPrefix(#"Remove "KitUI" from"#) == true)
    }

    // MARK: - Negative

    @Test func importingAnyModuleOfAProductUsesIt() {
        let issues = analyze(files: workspace(
            app: #".product(name: "KitAll", package: "kit")"#,
            appSource: "import KitCore"
        ))

        #expect(issues.isEmpty)
    }

    @Test func aProductReExportedByAnImportIsUsed() {
        var files = workspace(
            app: #".product(name: "KitUI", package: "kit")"#,
            appSource: "import Umbrella"
        )
        files["Package.swift"] = """
        let package = Package(
            name: "App",
            dependencies: [.package(path: "Packages/Kit")],
            targets: [
                .target(name: "Umbrella", dependencies: [.product(name: "KitUI", package: "kit")]),
                .target(name: "App", dependencies: ["Umbrella", .product(name: "KitUI", package: "kit")])
            ]
        )
        """
        files["Sources/Umbrella/Exports.swift"] = "@_exported import KitUI"

        #expect(analyze(files: files).isEmpty)
    }

    @Test func aProductWithATargetOutsideTheRunIsNotJudged() {
        var files = workspace(
            app: #".product(name: "KitAll", package: "kit")"#,
            appSource: "import Foundation"
        )
        // KitCore has no Swift files: it could be a C target imported under its module map's name.
        files.removeValue(forKey: "Packages/Kit/Sources/KitCore/Core.swift")

        #expect(analyze(files: files).isEmpty)
    }

    @Test func aProductThatCannotBeMatchedIsNotJudged() {
        let issues = analyze(files: workspace(
            app: #".product(name: "KitMissing", package: "kit")"#,
            appSource: "import Foundation"
        ))

        #expect(issues.isEmpty)
    }
}

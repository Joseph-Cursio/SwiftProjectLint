@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Runs the Undeclared Target Dependency visitor the way the cross-file engine does.
enum UndeclaredTargetDependencyHarness {

    static func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let visitor = UndeclaredTargetDependencyVisitor(fileCache: cache)
        visitor.setPattern(UndeclaredTargetDependency().pattern)

        for (name, ast) in cache.sorted(by: { $0.key < $1.key }) {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .undeclaredTargetDependency }
    }
}

@Suite
struct UndeclaredTargetDependencyVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        UndeclaredTargetDependencyHarness.analyze(files: files)
    }

    /// The three-layer manifest from the rule doc: Checkout and Persistence may use Domain only.
    private let layeredManifest = """
    // swift-tools-version:6.0
    import PackageDescription

    let package = Package(
        name: "App",
        targets: [
            .target(name: "Domain"),
            .target(name: "Persistence", dependencies: ["Domain"]),
            .target(name: "Checkout", dependencies: [.target(name: "Domain")]),
            .testTarget(name: "CheckoutTests", dependencies: ["Checkout"])
        ]
    )
    """

    // MARK: - Positive

    @Test func flagsImportOfUndeclaredSiblingTarget() throws {
        let issues = analyze(files: [
            "Package.swift": layeredManifest,
            "Sources/Domain/Order.swift": "struct Order {}",
            "Sources/Persistence/OrderStore.swift": "import Domain\nstruct OrderStore {}",
            "Sources/Checkout/CheckoutViewModel.swift": """
            import Foundation
            import Persistence

            final class CheckoutViewModel {}
            """
        ])

        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.filePath == "Sources/Checkout/CheckoutViewModel.swift")
        #expect(issue.lineNumber == 2)
        #expect(issue.message == "Target 'Checkout' imports 'Persistence' without declaring it as a dependency")
    }

    @Test func flagsTestTargetImportingTargetItDoesNotDeclare() throws {
        let issues = analyze(files: [
            "Package.swift": layeredManifest,
            "Sources/Domain/Order.swift": "struct Order {}",
            "Sources/Checkout/Checkout.swift": "import Domain",
            "Tests/CheckoutTests/CheckoutTests.swift": """
            @testable import Checkout
            @testable import Domain
            """
        ])

        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.message.contains("'CheckoutTests' imports 'Domain'"))
        #expect(issue.lineNumber == 2)
    }

    @Test func reportsEachModuleOncePerTargetAndCountsTheOtherFiles() throws {
        let issues = analyze(files: [
            "Package.swift": layeredManifest,
            "Sources/Persistence/Store.swift": "import Domain",
            "Sources/Checkout/B.swift": "import Persistence",
            "Sources/Checkout/A.swift": "import Persistence",
            "Sources/Checkout/C.swift": "import Persistence"
        ])

        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.filePath == "Sources/Checkout/A.swift")
        #expect(issue.message.contains("(and 2 other files)"))
    }

    @Test func matchesAHyphenatedTargetByItsModuleName() {
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "Tool",
                targets: [
                    .target(name: "tool-core"),
                    .executableTarget(name: "tool")
                ]
            )
            """,
            "Sources/tool-core/Core.swift": "struct Core {}",
            "Sources/tool/main.swift": "import tool_core"
        ])

        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("'tool_core'") == true)
    }

    @Test func honoursAnExplicitTargetPath() {
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "App",
                targets: [
                    .target(name: "Models", path: "Code/Models"),
                    .target(name: "Features", path: "Code/Features/")
                ]
            )
            """,
            "Code/Models/Model.swift": "struct Model {}",
            "Code/Features/Feature.swift": "import Models"
        ])

        #expect(issues.map(\.filePath) == ["Code/Features/Feature.swift"])
    }

    @Test func checksAPackageNestedInTheAnalysedTree() {
        let issues = analyze(files: [
            "Packages/Kit/Package.swift": """
            let package = Package(
                name: "Kit",
                targets: [.target(name: "KitCore"), .target(name: "KitUI")]
            )
            """,
            "Packages/Kit/Sources/KitCore/Core.swift": "struct Core {}",
            "Packages/Kit/Sources/KitUI/View.swift": "import KitCore"
        ])

        #expect(issues.map(\.filePath) == ["Packages/Kit/Sources/KitUI/View.swift"])
    }

    // MARK: - Negative: declared

    @Test func acceptsEverySpellingOfADeclaredTarget() {
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "App",
                targets: [
                    .target(name: "Alpha"),
                    .target(name: "Beta"),
                    .target(name: "Gamma"),
                    .target(
                        name: "Feature",
                        dependencies: [
                            "Alpha",
                            .target(name: "Beta", condition: .when(platforms: [.macOS])),
                            .byName(name: "Gamma")
                        ]
                    )
                ]
            )
            """,
            "Sources/Feature/Feature.swift": """
            import Alpha
            import Beta
            import Gamma
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test func ignoresModulesThatAreNotTargetsOfThisManifest() {
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "App",
                targets: [
                    .target(
                        name: "Feature",
                        dependencies: [.product(name: "ArgumentParser", package: "swift-argument-parser")]
                    )
                ]
            )
            """,
            "Sources/Feature/Feature.swift": """
            import Foundation
            import ArgumentParser
            import SomethingElseEntirely
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test func aTargetImportingItsOwnModuleIsNotAFinding() {
        let issues = analyze(files: [
            "Package.swift": #"let package = Package(name: "A", targets: [.target(name: "Feature")])"#,
            "Sources/Feature/Feature.swift": "import Feature"
        ])

        #expect(issues.isEmpty)
    }

    // MARK: - Negative: re-exports and conditional imports

    @Test func acceptsAModuleReExportedByADeclaredDependency() {
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "App",
                targets: [
                    .target(name: "Models"),
                    .target(name: "Core", dependencies: ["Models"]),
                    .target(name: "Umbrella", dependencies: ["Core"]),
                    .target(name: "Feature", dependencies: ["Umbrella"])
                ]
            )
            """,
            "Sources/Models/Model.swift": "struct Model {}",
            "Sources/Core/Exports.swift": "@_exported import Models",
            "Sources/Umbrella/Exports.swift": "@_exported import Core",
            "Sources/Feature/Feature.swift": """
            import Core
            import Models
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test func aPlainImportInADependencyIsNotAReExport() {
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "App",
                targets: [
                    .target(name: "Models"),
                    .target(name: "Core", dependencies: ["Models"]),
                    .target(name: "Feature", dependencies: ["Core"])
                ]
            )
            """,
            "Sources/Models/Model.swift": "struct Model {}",
            "Sources/Core/Core.swift": "import Models",
            "Sources/Feature/Feature.swift": "import Models"
        ])

        #expect(issues.map(\.filePath) == ["Sources/Feature/Feature.swift"])
    }

    @Test func acceptsAnImportGuardedByCanImportOfThatModule() {
        let issues = analyze(files: [
            "Package.swift": layeredManifest,
            "Sources/Checkout/Checkout.swift": """
            #if canImport(Persistence)
            import Persistence
            #endif
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test func canImportOfALongerNameDoesNotGuardTheImport() {
        let issues = analyze(files: [
            "Package.swift": layeredManifest,
            "Sources/Checkout/Checkout.swift": """
            #if canImport(PersistenceKit)
            import Persistence
            #endif
            """
        ])

        #expect(issues.count == 1)
    }
}

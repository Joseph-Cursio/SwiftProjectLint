@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct UnusedTargetDependencyVisitorTests {

    // MARK: - Helpers

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
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

    private let manifest = """
    let package = Package(
        name: "App",
        targets: [
            .target(name: "Domain"),
            .target(name: "Persistence"),
            .target(
                name: "Checkout",
                dependencies: [
                    "Domain",
                    "Persistence"
                ]
            )
        ]
    )
    """

    // MARK: - Positive

    @Test func flagsADeclaredDependencyNoFileImports() throws {
        let issues = analyze(files: [
            "Package.swift": manifest,
            "Sources/Domain/Order.swift": "struct Order {}",
            "Sources/Persistence/Store.swift": "struct Store {}",
            "Sources/Checkout/A.swift": "import Domain",
            "Sources/Checkout/B.swift": "import Foundation"
        ])

        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.filePath == "Package.swift")
        #expect(issue.lineNumber == 10)
        #expect(issue.message == "Target 'Checkout' declares a dependency on 'Persistence' but never imports it")
    }

    @Test func reportsAgainstTheNestedManifestThatDeclaresIt() {
        let issues = analyze(files: [
            "Packages/Kit/Package.swift": #"""
            let package = Package(
                name: "Kit",
                targets: [.target(name: "KitCore"), .target(name: "KitUI", dependencies: ["KitCore"])]
            )
            """#,
            "Packages/Kit/Sources/KitCore/Core.swift": "struct Core {}",
            "Packages/Kit/Sources/KitUI/View.swift": "import SwiftUI"
        ])

        #expect(issues.map(\.filePath) == ["Packages/Kit/Package.swift"])
    }

    @Test func judgesAMacroTargetThatIsNeitherImportedNorExpanded() {
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "Macros",
                targets: [.macro(name: "MacrosImpl"), .target(name: "Macros", dependencies: ["MacrosImpl"])]
            )
            """,
            "Sources/MacrosImpl/Plugin.swift": "import SwiftCompilerPlugin",
            "Sources/Macros/Macros.swift": "public struct Nothing {}"
        ])

        #expect(issues.count == 1)
    }

    // MARK: - Negative: used

    @Test func aTestableImportIsAUse() {
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "App",
                targets: [.target(name: "Checkout"), .testTarget(name: "CheckoutTests", dependencies: ["Checkout"])]
            )
            """,
            "Sources/Checkout/Checkout.swift": "struct Checkout {}",
            "Tests/CheckoutTests/CheckoutTests.swift": "@testable import Checkout"
        ])

        #expect(issues.isEmpty)
    }

    @Test func aModuleReExportedByAnImportIsUsed() {
        let issues = analyze(files: [
            "Package.swift": manifest,
            "Sources/Domain/Exports.swift": "@_exported import Persistence",
            "Sources/Persistence/Store.swift": "struct Store {}",
            "Sources/Checkout/Checkout.swift": "import Domain"
        ])

        #expect(issues.isEmpty)
    }

    @Test func anImportUnderCanImportIsAUse() {
        let issues = analyze(files: [
            "Package.swift": manifest,
            "Sources/Domain/Order.swift": "struct Order {}",
            "Sources/Persistence/Store.swift": "struct Store {}",
            "Sources/Checkout/Checkout.swift": """
            import Domain
            #if canImport(Persistence)
            import Persistence
            #endif
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test func anExternalMacroNamingTheDependencyIsAUse() {
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "Macros",
                targets: [.macro(name: "MacrosImpl"), .target(name: "Macros", dependencies: ["MacrosImpl"])]
            )
            """,
            "Sources/MacrosImpl/Plugin.swift": "import SwiftCompilerPlugin",
            "Sources/Macros/Macros.swift": """
            @freestanding(expression)
            public macro stringify<T>(_ value: T) -> (T, String) =
                #externalMacro(module: "MacrosImpl", type: "StringifyMacro")
            """
        ])

        #expect(issues.isEmpty)
    }

    // MARK: - Negative: not judged

    @Test func anExecutableDependencyIsNotJudged() {
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "Tool",
                targets: [.executableTarget(name: "tool"), .testTarget(name: "ToolTests", dependencies: ["tool"])]
            )
            """,
            "Sources/tool/main.swift": #"print("hi")"#,
            "Tests/ToolTests/ToolTests.swift": "import Foundation"
        ])

        #expect(issues.isEmpty)
    }

    @Test func aDependencyWithNoSwiftFilesIsNotJudged() {
        // A C target's module name comes from its module map, so `import zlib` may be how it is used.
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "App",
                targets: [.target(name: "CZlib"), .target(name: "Compression", dependencies: ["CZlib"])]
            )
            """,
            "Sources/Compression/Compression.swift": "import zlib"
        ])

        #expect(issues.isEmpty)
    }

    @Test func aTargetWithNoFilesInTheRunIsNotJudged() {
        let issues = analyze(files: [
            "Package.swift": manifest,
            "Sources/Domain/Order.swift": "struct Order {}",
            "Sources/Persistence/Store.swift": "struct Store {}"
        ])

        #expect(issues.isEmpty)
    }

    @Test func packageProductsAreNotJudged() {
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
            "Sources/Feature/Feature.swift": "import Foundation"
        ])

        #expect(issues.isEmpty)
    }

    @Test func aComputedDependencyListIsNotJudged() {
        let issues = analyze(files: [
            "Package.swift": """
            let shared: [Target.Dependency] = ["Persistence"]
            let package = Package(
                name: "App",
                targets: [.target(name: "Persistence"), .target(name: "Checkout", dependencies: shared)]
            )
            """,
            "Sources/Persistence/Store.swift": "struct Store {}",
            "Sources/Checkout/Checkout.swift": "import Foundation"
        ])

        #expect(issues.isEmpty)
    }
}

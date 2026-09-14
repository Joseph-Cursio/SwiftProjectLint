@testable import Core
import Testing

/// Undeclared Target Dependency across `.package(path:)` boundaries: imports of modules vended by a
/// local package whose manifest is in the run.
@Suite
struct UndeclaredProductDependencyTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        UndeclaredTargetDependencyHarness.analyze(files: files)
    }

    /// App depends on Kit; Kit depends on Models. Nothing re-exports anything unless a test adds it.
    private let workspace: [String: String] = [
        "Package.swift": """
        let package = Package(
            name: "App",
            dependencies: [.package(path: "Packages/Kit")],
            targets: [
                .target(name: "App", dependencies: [.product(name: "KitUI", package: "kit")])
            ]
        )
        """,
        "Packages/Kit/Package.swift": """
        let package = Package(
            name: "Kit",
            products: [
                .library(name: "KitUI", targets: ["KitUI"]),
                .library(name: "KitCore", targets: ["KitCore"])
            ],
            dependencies: [.package(path: "../Models")],
            targets: [
                .target(name: "KitCore", dependencies: [.product(name: "Models", package: "Models")]),
                .target(name: "KitUI", dependencies: ["KitCore"]),
                .target(name: "KitInternals")
            ]
        )
        """,
        "Packages/Kit/Sources/KitCore/Core.swift": "import Models",
        "Packages/Kit/Sources/KitUI/View.swift": "import KitCore",
        "Packages/Kit/Sources/KitInternals/Internals.swift": "struct Internals {}",
        "Packages/Models/Package.swift": """
        let package = Package(
            name: "Models",
            products: [.library(name: "Models", targets: ["Models"])],
            targets: [.target(name: "Models")]
        )
        """,
        "Packages/Models/Sources/Models/Model.swift": "struct Model {}"
    ]

    private func workspace(appImports: String, overriding overrides: [String: String] = [:]) -> [String: String] {
        workspace.merging(["Sources/App/App.swift": appImports]) { _, new in new }
            .merging(overrides) { _, new in new }
    }

    // MARK: - Positive

    @Test func flagsAModuleOfADirectPathDependencyThatIsNotDeclared() throws {
        let issues = analyze(files: workspace(appImports: "import KitUI\nimport KitCore"))

        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.filePath == "Sources/App/App.swift")
        #expect(issue.lineNumber == 2)
        #expect(issue.message == "Target 'App' imports 'KitCore' without declaring it as a dependency")
        #expect(issue.suggestion?.contains(#"Add .product(name: "KitCore", package: "kit")"#) == true)
        #expect(issue.suggestion?.contains("Also add") == false)
    }

    @Test func flagsAModuleReachedOnlyThroughAnotherPackage() throws {
        let issues = analyze(files: workspace(appImports: "import KitUI\nimport Models"))

        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.message.contains("imports 'Models'"))
        #expect(issue.suggestion?.contains(#".product(name: "Models", package: "models")"#) == true)
        #expect(issue.suggestion?.contains("Also add 'models' to this package's dependencies") == true)
    }

    @Test func namesTheMissingProductWhenNoProductVendsTheModule() throws {
        let issues = analyze(files: workspace(appImports: "import KitInternals"))

        let issue = try #require(issues.first)
        #expect(issue.suggestion?.hasPrefix("No library product of 'kit' vends 'KitInternals'") == true)
    }

    @Test func reusesTheManifestsOwnSpellingForAPackageReachedThroughParentDirectories() throws {
        // An example package nested in the library it demonstrates, depending on it through `../..`.
        let issues = analyze(files: [
            "Package.swift": """
            let package = Package(
                name: "Idempotency",
                products: [.library(name: "Idempotency", targets: ["Idempotency"])],
                targets: [.target(name: "Idempotency")]
            )
            """,
            "Sources/Idempotency/Key.swift": "struct Key {}",
            "examples/sample/Package.swift": """
            let package = Package(
                name: "Sample",
                dependencies: [.package(path: "../..")],
                targets: [
                    .target(name: "Sample", dependencies: [.product(name: "Idempotency", package: "Idempotency")]),
                    .testTarget(name: "SampleTests", dependencies: ["Sample"])
                ]
            )
            """,
            "examples/sample/Sources/Sample/Sample.swift": "import Idempotency",
            "examples/sample/Tests/SampleTests/SampleTests.swift": "import Idempotency"
        ])

        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.filePath == "examples/sample/Tests/SampleTests/SampleTests.swift")
        #expect(issue.suggestion?.contains(#".product(name: "Idempotency", package: "Idempotency")"#) == true)
    }

    // MARK: - Negative

    @Test func acceptsEveryModuleOfADeclaredProduct() {
        let files = workspace(appImports: "import KitUI\nimport KitCore", overriding: [
            "Package.swift": """
            let package = Package(
                name: "App",
                dependencies: [.package(path: "Packages/Kit")],
                targets: [.target(name: "App", dependencies: ["KitUI", .product(name: "KitCore", package: "kit")])]
            )
            """
        ])

        #expect(analyze(files: files).isEmpty)
    }

    @Test func acceptsAModuleReExportedAcrossPackages() {
        let files = workspace(appImports: "import KitUI\nimport KitCore\nimport Models", overriding: [
            "Packages/Kit/Sources/KitCore/Core.swift": "@_exported import Models",
            "Packages/Kit/Sources/KitUI/View.swift": "@_exported import KitCore"
        ])

        #expect(analyze(files: files).isEmpty)
    }

    @Test func exemptsAPackageWhoseDeclaredProductCannotBeMatched() {
        // Kit's products are computed, so "KitUI" could vend KitCore, and KitCore could re-export Models.
        let files = workspace(appImports: "import KitCore\nimport Models", overriding: [
            "Packages/Kit/Package.swift": """
            let names = ["KitUI"]
            let package = Package(
                name: "Kit",
                products: [.library(name: names[0], targets: ["KitUI", "KitCore"])],
                dependencies: [.package(path: "../Models")],
                targets: [
                    .target(name: "KitCore", dependencies: [.product(name: "Models", package: "Models")]),
                    .target(name: "KitUI", dependencies: ["KitCore"])
                ]
            )
            """,
            "Packages/Kit/Sources/KitCore/Core.swift": "@_exported import Models"
        ])

        #expect(analyze(files: files).isEmpty)
    }

    @Test func judgesNothingFromAPathPackageOutsideTheRun() {
        var files = workspace(appImports: "import KitUI\nimport KitCore\nimport Models")
        files.removeValue(forKey: "Packages/Kit/Package.swift")
        files.removeValue(forKey: "Packages/Models/Package.swift")

        #expect(analyze(files: files).isEmpty)
    }

    @Test func aRemoteProductIsNeverJudged() {
        let files = workspace(appImports: "import KitUI\nimport ArgumentParser", overriding: [
            "Package.swift": """
            let package = Package(
                name: "App",
                dependencies: [
                    .package(path: "Packages/Kit"),
                    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
                ],
                targets: [.target(name: "App", dependencies: [.product(name: "KitUI", package: "kit")])]
            )
            """
        ])

        #expect(analyze(files: files).isEmpty)
    }
}

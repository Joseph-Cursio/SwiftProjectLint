import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct PackageGraphTests {

    // MARK: - Fixture

    /// An app at the root depending on two local packages, one of which depends on the other.
    private let workspace: [String: String] = [
        "Package.swift": """
        let package = Package(
            name: "App",
            dependencies: [
                .package(path: "Packages/Models"),
                .package(name: "KitPackage", path: "Packages/Kit"),
                .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
            ],
            targets: [
                .target(name: "AppCore"),
                .target(
                    name: "App",
                    dependencies: [
                        "AppCore",
                        "Models",
                        .product(name: "KitUI", package: "kit"),
                        .product(name: "Kit", package: "KitPackage"),
                        .product(name: "Missing", package: "kit"),
                        .product(name: "ArgumentParser", package: "swift-argument-parser")
                    ]
                )
            ]
        )
        """,
        "Sources/AppCore/AppCore.swift": "struct AppCore {}",
        "Sources/App/App.swift": "import KitUI",
        "Packages/Models/Package.swift": """
        let package = Package(
            name: "Models",
            products: [.library(name: "Models", targets: ["Models"])],
            targets: [.target(name: "Models")]
        )
        """,
        "Packages/Models/Sources/Models/Model.swift": "struct Model {}",
        "Packages/Kit/Package.swift": """
        let package = Package(
            name: "Kit",
            products: [
                .library(name: "Kit", targets: ["KitCore", "KitUI"]),
                .library(name: "KitUI", targets: ["KitUI"])
            ],
            dependencies: [.package(path: "../Models")],
            targets: [
                .target(name: "KitCore", dependencies: [.product(name: "Models", package: "Models")]),
                .target(name: "KitUI", dependencies: ["KitCore"])
            ]
        )
        """,
        "Packages/Kit/Sources/KitCore/Core.swift": "@_exported import Models",
        "Packages/Kit/Sources/KitUI/View.swift": "@_exported import KitCore"
    ]

    private func graph(_ files: [String: String]) -> PackageGraph {
        PackageGraph(fileCache: files.mapValues { Parser.parse(source: $0) })
    }

    private func node(_ directory: String, in graph: PackageGraph) throws -> PackageGraph.Node {
        try #require(graph.nodes.first { $0.manifest.directory == directory })
    }

    private func appDependencies(in graph: PackageGraph) throws -> [PackageGraph.ResolvedDependency] {
        let app = try node("", in: graph)
        let target = try #require(app.manifest.targets.first { $0.name == "App" })
        return try #require(target.dependencies).map { graph.resolve($0, in: app) }
    }

    // MARK: - Paths

    @Test func resolvesPathsAgainstTheManifestDirectory() {
        #expect(PackageGraph.resolve("Packages/Models", from: "") == "Packages/Models/")
        #expect(PackageGraph.resolve("../Models", from: "Packages/Kit/") == "Packages/Models/")
        #expect(PackageGraph.resolve("./Vendor/", from: "Packages/Kit/") == "Packages/Kit/Vendor/")
        #expect(PackageGraph.resolve("..", from: "Packages/")?.isEmpty == true)
    }

    @Test func refusesAPathThatLeavesTheAnalysedTree() {
        #expect(PackageGraph.resolve("../Sibling", from: "") == nil)
        #expect(PackageGraph.resolve("/Users/someone/Kit", from: "") == nil)
    }

    @Test func followsPathDependenciesTransitively() throws {
        let graph = graph(workspace)
        let app = try node("", in: graph)

        #expect(graph.directPathPackages(of: app).map(\.package.manifest.directory) == [
            "Packages/Models/", "Packages/Kit/"
        ])
        let kit = try node("Packages/Kit/", in: graph)
        #expect(graph.reachablePathPackages(of: kit).map(\.manifest.directory) == ["Packages/Models/"])
    }

    // MARK: - Resolving dependencies

    @Test func resolvesEachSpellingOfADependency() throws {
        let resolved = try appDependencies(in: graph(workspace))
        try #require(resolved.count == 6)

        guard case .localTarget(let target) = resolved[0] else { Issue.record("AppCore"); return }
        #expect(target.name == "AppCore")

        // A plain string that is not a local target names a product of a direct path dependency.
        guard case let .product(models, modelsModules, _) = resolved[1] else { Issue.record("Models"); return }
        #expect(models.name == "Models")
        #expect(modelsModules == ["Models"])

        // `package:` by SwiftPM identity — the lowercased last path component.
        guard case .product(_, let kitUIModules, _) = resolved[2] else { Issue.record("KitUI"); return }
        #expect(kitUIModules == ["KitUI"])

        // `package:` by the older `.package(name:path:)` name.
        guard case .product(_, let kitModules, _) = resolved[3] else { Issue.record("Kit"); return }
        #expect(kitModules == ["KitCore", "KitUI"])

        guard case .unresolvedProduct(let packages) = resolved[4] else { Issue.record("Missing"); return }
        #expect(packages.map(\.manifest.directory) == ["Packages/Kit/"])

        guard case .external = resolved[5] else { Issue.record("ArgumentParser"); return }
    }

    @Test func aPackageWithUnreadableProductsIsUnresolvedNotExternal() throws {
        var files = workspace
        files["Packages/Kit/Package.swift"] = """
        let name = "KitUI"
        let package = Package(
            name: "Kit",
            products: [.library(name: name, targets: ["KitUI"])],
            targets: [.target(name: "KitUI")]
        )
        """
        let resolved = try appDependencies(in: graph(files))

        guard case .unresolvedProduct = resolved[2] else {
            Issue.record("a product of an unreadable list must not read as outside the run")
            return
        }
    }

    @Test func aPlainStringIsUnresolvedWhereAProductListCannotBeRead() throws {
        var files = workspace
        files["Packages/Models/Package.swift"] = """
        let name = "Models"
        let package = Package(
            name: "Models",
            products: [.library(name: name, targets: ["Models"])],
            targets: [.target(name: "Models")]
        )
        """
        let resolved = try appDependencies(in: graph(files))

        // "Models" could be that unreadable list's product, so Models must not be judged as undeclared.
        guard case .unresolvedProduct(let packages) = resolved[1] else { Issue.record("Models"); return }
        #expect(packages.map(\.manifest.directory) == ["Packages/Models/"])
    }

    @Test func aPathPackageOutsideTheRunIsExternal() throws {
        var files = workspace
        files.removeValue(forKey: "Packages/Kit/Package.swift")
        let resolved = try appDependencies(in: graph(files))

        guard case .external = resolved[2] else { Issue.record("KitUI"); return }
    }

    // MARK: - Re-exports

    @Test func followsReExportsAcrossPackageBoundaries() {
        let reachable = graph(workspace).withReexports(of: ["KitUI"])
        #expect(reachable == ["KitUI", "KitCore", "Models"])
    }
}

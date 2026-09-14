import SwiftParser
@testable import SwiftProjectLintRules
import Testing

/// What a manifest says about the package as a whole: its name, library products, and path
/// dependencies — the facts that let one manifest be reached from another.
@Suite
struct PackageManifestPackageLevelTests {

    private func read(_ source: String) throws -> PackageManifest {
        try #require(PackageManifest(source: Parser.parse(source: source), directory: ""))
    }

    @Test func readsTheNameProductsAndPathDependencies() throws {
        let manifest = try read("""
        let package = Package(
            name: "Kit",
            products: [
                .library(name: "Kit", targets: ["KitCore", "KitUI"]),
                .library(name: "KitDynamic", type: .dynamic, targets: ["KitCore"]),
                .executable(name: "kit-tool", targets: ["KitTool"])
            ],
            dependencies: [
                .package(path: "../Models"),
                .package(name: "Legacy", path: "Vendor/legacy-kit"),
                .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
            ],
            targets: [.target(name: "KitCore"), .target(name: "KitUI"), .executableTarget(name: "KitTool")]
        )
        """)

        #expect(manifest.packageName == "Kit")
        #expect(manifest.libraryProducts?.map(\.name) == ["Kit", "KitDynamic"])
        #expect(manifest.libraryProducts?.first?.targets == ["KitCore", "KitUI"])
        #expect(manifest.pathDependencies.map(\.path) == ["../Models", "Vendor/legacy-kit"])
        #expect(manifest.pathDependencies.map(\.name) == [nil, "Legacy"])
        #expect(manifest.pathDependencies.map(\.identity) == ["models", "legacy-kit"])
    }

    @Test func readsThePackageOfAProductDependency() throws {
        let manifest = try read("""
        let package = Package(
            name: "App",
            targets: [
                .target(
                    name: "Feature",
                    dependencies: ["Kit", .product(name: "KitUI", package: "kit")]
                )
            ]
        )
        """)

        let dependencies = try #require(manifest.targets.first?.dependencies)
        #expect(dependencies.map(\.package) == [nil, "kit"])
        #expect(dependencies.map(\.isPackageProduct) == [false, true])
    }

    @Test func aComputedProductMakesTheProductListUnknownButNotTheManifest() throws {
        let manifest = try read("""
        let productName = "Kit"
        let package = Package(
            name: "Kit",
            products: [.library(name: productName, targets: ["KitCore"])],
            targets: [.target(name: "KitCore")]
        )
        """)

        #expect(manifest.libraryProducts == nil)
        #expect(manifest.targets.map(\.name) == ["KitCore"])
    }

    @Test func aComputedDependencyPathIsLeftOutRatherThanGuessed() throws {
        let manifest = try read("""
        let root = "../"
        let package = Package(
            name: "App",
            dependencies: [.package(path: root + "Models"), .package(path: "../Kit")],
            targets: []
        )
        """)

        #expect(manifest.pathDependencies.map(\.path) == ["../Kit"])
    }

    @Test func productsAndDependenciesDoNotReadAsTargets() throws {
        let manifest = try read("""
        let package = Package(
            name: "Kit",
            products: [.library(name: "Kit", targets: ["KitCore"])],
            dependencies: [.package(path: "../Models")],
            targets: [.target(name: "KitCore", dependencies: [.product(name: "Models", package: "Models")])]
        )
        """)

        #expect(manifest.targets.map(\.name) == ["KitCore"])
    }
}

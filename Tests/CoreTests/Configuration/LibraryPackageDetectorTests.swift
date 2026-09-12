@testable import Core
import Foundation
@testable import SwiftProjectLintConfig
import Testing

/// A nested package that publishes a `.library` product is a library whatever the analysed root
/// is — the case `TargetType` cannot reach, because it is resolved once from the root.
///
/// Without this, `include_nested_packages` pulled a published library into a run classified as an
/// app and `publicInAppTarget` fired on its whole API: 462 findings on one subject, 38% of the
/// run, every one wrong (#108).
@Suite("Nested library packages are not app targets")
struct LibraryPackageDetectorTests {

    private func makeTree(
        nested: [(name: String, manifest: String)],
        rootHasManifest: Bool = false
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibPkgDetector-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if rootHasManifest {
            try "// swift-tools-version: 6.1".write(
                to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
            )
        }
        for package in nested {
            let directory = root.appendingPathComponent(package.name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try package.manifest.write(
                to: directory.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8
            )
        }
        return root
    }

    private static let libraryManifest = """
    // swift-tools-version: 6.1
    import PackageDescription
    let package = Package(
        name: "Lib",
        products: [.library(name: "Lib", targets: ["Lib"])],
        targets: [.target(name: "Lib")]
    )
    """

    private static let executableManifest = """
    // swift-tools-version: 6.1
    import PackageDescription
    let package = Package(
        name: "Exe",
        products: [.executable(name: "exe", targets: ["Exe"])],
        targets: [.executableTarget(name: "Exe")]
    )
    """

    @Test("a nested package publishing a library is reported, with a trailing separator")
    func reportsLibraryPackages() throws {
        let root = try makeTree(nested: [("Bridge", Self.libraryManifest)])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(LibraryPackageDetector.libraryPackagePaths(in: root.path) == ["Bridge/"])
    }

    /// **The discrimination that keeps the rule useful.** A package shipping only executables is a
    /// program, and `public` in it is over-exposure exactly as it is in an app — so it must still
    /// be flagged. Excluding every nested package would have been the easy fix and the wrong one.
    @Test("a nested package publishing only executables is not reported")
    func ignoresExecutableOnlyPackages() throws {
        let root = try makeTree(nested: [("Tool", Self.executableManifest)])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(LibraryPackageDetector.libraryPackagePaths(in: root.path).isEmpty)
    }

    /// SwiftUMLBridge declares both, and one library product is enough: the framework is consumed
    /// by SwiftPM dependents whatever else the package also ships.
    @Test("a package publishing both is a library")
    func bothProductsCountsAsLibrary() throws {
        let mixed = """
        // swift-tools-version: 6.1
        import PackageDescription
        let package = Package(
            name: "Mixed",
            products: [
                .library(name: "Framework", targets: ["Framework"]),
                .executable(name: "cli", targets: ["CLI"])
            ]
        )
        """
        let root = try makeTree(nested: [("Mixed", mixed)])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(LibraryPackageDetector.libraryPackagePaths(in: root.path) == ["Mixed/"])
    }

    @Test("several nested packages are reported in a stable order")
    func reportsEveryLibraryPackageSorted() throws {
        let root = try makeTree(nested: [
            ("Zed", Self.libraryManifest),
            ("Alpha", Self.libraryManifest),
            ("Tool", Self.executableManifest)
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(LibraryPackageDetector.libraryPackagePaths(in: root.path) == ["Alpha/", "Zed/"])
    }

    /// The root's own manifest is `TargetType`'s business — a library root already disables the
    /// rule outright — so it must not appear here as a path to exclude.
    @Test("the analysed root itself is never reported")
    func rootIsNotReported() throws {
        let root = try makeTree(nested: [], rootHasManifest: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(LibraryPackageDetector.libraryPackagePaths(in: root.path).isEmpty)
    }

    @Test("a directory with no manifest is not a package")
    func plainDirectoryIsNotAPackage() throws {
        let root = try makeTree(nested: [])
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true
        )

        #expect(LibraryPackageDetector.libraryPackagePaths(in: root.path).isEmpty)
    }
}

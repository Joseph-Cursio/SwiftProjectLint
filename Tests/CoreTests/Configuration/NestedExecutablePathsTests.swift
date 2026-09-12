@testable import Core
import Foundation
@testable import SwiftProjectLintConfig
import Testing

/// `print` to stdout is a CLI's interface, not logging — and a CLI is often a package *beside* an
/// Xcode app rather than the analysed root.
///
/// `executableSourcePaths(in:)` reads the manifest at the root and nothing else, so an
/// `.xcodeproj` root never found the executable target in a nested package: five findings on
/// `swiftumlbridge` for the `--list` output the user asked for (#112).
@Suite("Executable sources are found in nested packages too")
struct NestedExecutablePathsTests {

    private func makeTree(_ packages: [(name: String, manifest: String)]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NestedExec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for package in packages {
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

    private static let cliManifest = """
    // swift-tools-version: 6.1
    import PackageDescription
    let package = Package(
        name: "Bridge",
        products: [
            .library(name: "Framework", targets: ["Framework"]),
            .executable(name: "tool", targets: ["tool"])
        ],
        targets: [
            .target(name: "Framework"),
            .executableTarget(name: "tool")
        ]
    )
    """

    /// The path is reported **relative to the analysed root**, since that is what an
    /// `excludedPaths` override matches against.
    @Test("a nested package's executable target is found, root-relative")
    func findsNestedExecutableTarget() throws {
        let root = try makeTree([("Bridge", Self.cliManifest)])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(
            ExecutableTargetDetector.nestedExecutableSourcePaths(in: root.path)
                == ["Bridge/Sources/tool/"]
        )
    }

    /// The library target in the same package is **not** excluded. A framework that prints is a
    /// separate question, and two of the three remaining findings on the subject are genuine —
    /// `print(error)` in a `catch` is exactly what this rule is for.
    @Test("a nested package's library target is not treated as executable")
    func doesNotExcludeTheLibraryTarget() throws {
        let root = try makeTree([("Bridge", Self.cliManifest)])
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = ExecutableTargetDetector.nestedExecutableSourcePaths(in: root.path)
        #expect(!paths.contains { $0.contains("Framework") })
    }

    @Test("a package with no executable product contributes nothing")
    func ignoresLibraryOnlyPackages() throws {
        let libraryOnly = """
        // swift-tools-version: 6.1
        import PackageDescription
        let package = Package(
            name: "Lib",
            products: [.library(name: "Lib", targets: ["Lib"])],
            targets: [.target(name: "Lib")]
        )
        """
        let root = try makeTree([("Lib", libraryOnly)])
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(ExecutableTargetDetector.nestedExecutableSourcePaths(in: root.path).isEmpty)
    }

    /// The analysed root's own manifest stays `executableSourcePaths(in:)`'s job, so it must not
    /// be reported twice.
    @Test("the analysed root is not reported as a nested package")
    func rootIsNotNested() throws {
        let root = try makeTree([])
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.cliManifest.write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )

        #expect(ExecutableTargetDetector.nestedExecutableSourcePaths(in: root.path).isEmpty)
        #expect(ExecutableTargetDetector.executableSourcePaths(in: root.path) == ["Sources/tool/"])
    }
}

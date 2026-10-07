@testable import Core
import Foundation
import Testing

/// What makes a nested package, and what its manifest says — the shared spec's amendment 3,
/// checked through `ProjectLinter`.
///
/// A package boundary is a manifest (amendment F), not anything named `Package.swift`: a boundary
/// that is not one takes every file beside it out of the universe, so a function building one of
/// their types is offered as a candidate though the target compiles that type.
@Suite("The package purity's package boundaries")
struct PackagePurityManifestTests {

    @Test("a source file named Package.swift inside a target is no package boundary", arguments: [false, true])
    func sourceFileNamedPackageIsNoBoundary(includeNestedPackages: Bool) async throws {
        // SwiftPM compiles `Models/Package.swift` into `App` along with `Models/Item.swift`.
        let root = try PackagePurityFixtures.makeProject([
            "Package.swift": Self.rootManifest(dependencies: ""),
            "Sources/App/Models/Package.swift": "struct Package: Equatable { let name: String }\n",
            "Sources/App/Models/Item.swift": PackagePurityFixtures.refutingItem,
            "Sources/App/Callers.swift": PackagePurityFixtures.callers
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }
        await Self.expectItemRefutes(
            at: root, holding: ["Sources/App/Models/Item.swift"], includeNestedPackages: includeNestedPackages
        )
    }

    @Test("a directory named Package.swift is no package boundary")
    func directoryNamedPackageIsNoBoundary() async throws {
        let root = try PackagePurityFixtures.makeProject([
            "Package.swift": Self.rootManifest(dependencies: ""),
            "Odd/Package.swift/README.md": "Not a manifest.\n",
            "Odd/Sources/Odd/Item.swift": PackagePurityFixtures.refutingItem,
            "Sources/App/Callers.swift": PackagePurityFixtures.callers
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }
        await Self.expectItemRefutes(at: root, holding: ["Odd/Sources/Odd/Item.swift"])
    }

    @Test("a dangling Package.swift link is no package boundary, and a dependency on it is not doubt")
    func danglingManifestLinkIsNoBoundary() async throws {
        // Both repositories once read this differently: one as root-owned files, the other as an
        // unreadable manifest, hence doubt and every nested package. Nothing SwiftPM can load is a
        // manifest, so `Ghost/` is the root's, and the unrelated `Demo/` stays out.
        let root = try PackagePurityFixtures.makeProject([
            "Package.swift": Self.rootManifest(dependencies: #".package(path: "Ghost")"#),
            "Ghost/Sources/Ghost/Item.swift": PackagePurityFixtures.refutingItem,
            "Demo/Package.swift": "// swift-tools-version:6.0\n",
            "Demo/Sources/Demo/Row.swift": Self.demoRow,
            "Sources/App/Callers.swift": PackagePurityFixtures.callers
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }
        try PackagePurityFixtures.symlink("Ghost/Package.swift", to: "/nonexistent/Package.swift", in: root)
        await Self.expectItemRefutes(at: root, holding: ["Ghost/Sources/Ghost/Item.swift"])
        #expect(await PackagePurityFixtures.universe(at: root).contains("Demo/Sources/Demo/Row.swift") == false)
    }

    @Test("an unreadable manifest is a boundary, and doubt where the closure reads it")
    func unreadableManifestIsABoundaryAndDoubt() async throws {
        let root = try PackagePurityFixtures.makeProject([
            "Package.swift": Self.rootManifest(dependencies: #".package(path: "Locked")"#),
            "Locked/Package.swift": "// swift-tools-version:6.0\n",
            "Locked/Sources/Locked/Item.swift": PackagePurityFixtures.refutingItem,
            "Demo/Package.swift": "// swift-tools-version:6.0\n",
            "Demo/Sources/Demo/Row.swift": Self.demoRow,
            "Sources/App/Callers.swift": PackagePurityFixtures.callers
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let doubtful = try Self.lock("Locked/Package.swift", in: root)
        // The root reads `Locked/`'s manifest and cannot: it may depend on anything, so `Demo/` is in.
        #expect(await PackagePurityFixtures.universe(at: root) == [
            "Demo/Sources/Demo/Row.swift", "Locked/Sources/Locked/Item.swift", "Sources/App/Callers.swift"
        ])

        // Unreached, it is still a boundary: nothing the root compiles reads it.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: doubtful)
        try Self.rootManifest(dependencies: "")
            .write(toFile: root + "/Package.swift", atomically: true, encoding: .utf8)
        _ = try Self.lock("Demo/Package.swift", in: root)
        #expect(await PackagePurityFixtures.universe(at: root) == ["Sources/App/Callers.swift"])
    }

    // MARK: - Fixtures

    static func rootManifest(dependencies: String) -> String {
        """
        // swift-tools-version:6.0
        import PackageDescription
        let package = Package(
            name: "App",
            dependencies: [\(dependencies)],
            targets: [.executableTarget(name: "App")]
        )
        """
    }

    /// A refuting `Row` no subject builds: in the universe or not, it moves no candidate, so only
    /// the universe itself says whether its package was taken.
    static let demoRow = "import Foundation\nstruct Row { let id = UUID(); let n: Int }\n"

    /// The universe holds every path in `holding`, and the `Item` there refutes `countOf`.
    static func expectItemRefutes(
        at root: String,
        holding paths: Set<String>,
        includeNestedPackages: Bool = false,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        let configuration = LintConfiguration(includeNestedPackages: includeNestedPackages)
        let universe = await PackagePurityFixtures.universe(at: root, configuration: configuration)
        #expect(paths.isSubset(of: universe), "universe: \(universe)", sourceLocation: sourceLocation)
        let found = PackagePurityFixtures.symbols(await ProjectLinter().analyzeProject(
            at: root,
            detector: PatternRegistryFactory.createConfiguredSystem().detector,
            configuration: configuration
        ))
        #expect(found.contains("sentinelAdd"), "the rule produced nothing", sourceLocation: sourceLocation)
        #expect(found.contains("countOf") == false, "the Item left the table", sourceLocation: sourceLocation)
    }

    /// Makes the file at `relative` unreadable and returns its path.
    static func lock(_ relative: String, in root: String) throws -> String {
        let path = root + "/" + relative
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        try #require(FileManager.default.isReadableFile(atPath: path) == false, "running as root?")
        return path
    }
}

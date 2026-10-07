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

    @Test("an Xcode project beside the root manifest takes every nested package", arguments: [
        "App.xcodeproj", "App.xcworkspace"
    ])
    func xcodeProjectBesideTheManifestTakesEveryPackage(container: String) async throws {
        // The manifest builds a command-line tool and names no local package; the Xcode project
        // builds the app, and its app target links `LocalPackages/Feature`. Bounded by the
        // manifest alone, `Feature` left the table and `countOf` was offered.
        let files = [
            "Package.swift": """
            // swift-tools-version:6.0
            import PackageDescription
            let package = Package(name: "Tool", targets: [.executableTarget(name: "Tool")])
            """,
            "LocalPackages/Feature/Package.swift": "// swift-tools-version:6.0\n",
            "LocalPackages/Feature/Sources/Feature/Item.swift": PackagePurityFixtures.refutingItem,
            "App/Callers.swift": PackagePurityFixtures.callers
        ]
        let control = try await PackagePurityFixtures.candidates(in: files)
        #expect(control.contains("countOf"), "control: without the Xcode project, Feature is not compiled")

        var withXcode = files
        withXcode["\(container)/project.pbxproj"] = "// !$*UTF8*$!\n"
        let root = try PackagePurityFixtures.makeProject(withXcode)
        defer { try? FileManager.default.removeItem(atPath: root) }
        await Self.expectItemRefutes(at: root, holding: ["LocalPackages/Feature/Sources/Feature/Item.swift"])
    }

    // MARK: - The joint review critic's fixtures

    // Each is `critic/<name>` from the review, file for file: `tokenCount` builds a `Tok` that
    // mints a `UUID`, declared in a package the root compiles by a route the bound did not read.
    // Each runs with a plain `Tok` too, so a candidate that vanishes vanished for the `UUID`.

    @Test("s6v: a dependency named only in Package@swift-6.0.swift is compiled")
    func versionSpecificManifestDependency() async throws {
        try await Self.expectTokenCountRefutes(tokAt: "Packages/A/Sources/A/Tok.swift", files: [
            "Package.swift": """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(name: "Root", targets: [.target(name: "App")])
            """,
            "Package@swift-6.0.swift": Self.dependsOnA,
            "Packages/A/Package.swift": Self.libraryManifest("A")
        ])
    }

    @Test("s6c: the same dependency in Package.swift is compiled")
    func plainManifestDependency() async throws {
        try await Self.expectTokenCountRefutes(tokAt: "Packages/A/Sources/A/Tok.swift", files: [
            "Package.swift": Self.dependsOnA,
            "Packages/A/Package.swift": Self.libraryManifest("A")
        ])
    }

    @Test("s7: a root target whose path lies in a nested package compiles that package's files")
    func targetPathIntoNestedPackage() async throws {
        try await Self.expectTokenCountRefutes(tokAt: "Core/Sources/Core/Tok.swift", files: [
            "Package.swift": """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(
                name: "Root",
                targets: [
                    .target(name: "Core", path: "Core/Sources/Core"),
                    .target(name: "App", dependencies: ["Core"])
                ]
            )
            """,
            "Core/Package.swift": Self.libraryManifest("Core")
        ], subject: Self.tokenCount.replacingOccurrences(of: "import A", with: "import Core"))
    }

    @Test("s11: a dependency through a link reaches the walked package the link points to")
    func dependencyThroughALinkedDirectory() async throws {
        // `Packages/Core` links to `Vendor/Core`. The walk does not follow a linked directory, so
        // the package it finds is `Vendor/Core`; matched by spelling, `Packages/Core` named none.
        try await Self.expectTokenCountRefutes(
            tokAt: "Vendor/Core/Sources/Core/Tok.swift",
            files: [
                "Package.swift": Self.dependsOnCore(spelled: "Packages/Core"),
                "Vendor/Core/Package.swift": Self.libraryManifest("Core")
            ],
            links: [(link: "Packages/Core", destination: "../Vendor/Core")],
            subject: Self.tokenCount.replacingOccurrences(of: "import A", with: "import Core")
        )
    }

    @Test(
        "a dependency spelled in another letter case reaches its package on a case-insensitive volume",
        .enabled(if: Self.temporaryVolumeIgnoresCase)
    )
    func dependencyInAnotherCase() async throws {
        try await Self.expectTokenCountRefutes(
            tokAt: "Packages/Core/Sources/Core/Tok.swift",
            files: [
                "Package.swift": Self.dependsOnCore(spelled: "packages/core"),
                "Packages/Core/Package.swift": Self.libraryManifest("Core")
            ],
            subject: Self.tokenCount.replacingOccurrences(of: "import A", with: "import Core")
        )
    }

    // MARK: - Fixtures

    /// The critic's subject, `Sources/App/App.swift`.
    static let tokenCount = """
    import A
    public func tokenCount(_ n: Int) -> Int {
        Tok(n: n).n * 2
    }
    """

    static let dependsOnA = """
    // swift-tools-version:6.0
    import PackageDescription
    let package = Package(name: "Root", dependencies: [.package(path: "Packages/A")], \
    targets: [.target(name: "App", dependencies: [.product(name: "A", package: "A")])])
    """

    static func dependsOnCore(spelled path: String) -> String {
        """
        // swift-tools-version:5.9
        import PackageDescription
        let package = Package(name: "Root", dependencies: [.package(path: "\(path)")], \
        targets: [.target(name: "App", dependencies: [.product(name: "Core", package: "Core")])])
        """
    }

    /// Whether the temporary directory's volume finds a path in either letter case, as APFS does
    /// by default.
    static let temporaryVolumeIgnoresCase: Bool = {
        let probe = FileManager.default.temporaryDirectory.appendingPathComponent("CaseProbe-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: probe.path, contents: Data()) else { return false }
        defer { try? FileManager.default.removeItem(at: probe) }
        return FileManager.default.fileExists(atPath: probe.path.lowercased().replacingOccurrences(
            of: probe.lastPathComponent.lowercased(), with: probe.lastPathComponent.uppercased()
        ))
    }()

    static func libraryManifest(_ name: String) -> String {
        """
        // swift-tools-version:5.9
        import PackageDescription
        let package = Package(name: "\(name)", products: [.library(name: "\(name)", targets: ["\(name)"])], \
        targets: [.target(name: "\(name)")])
        """
    }

    /// `files`, `Sources/App/App.swift` and a `Tok` at `tokAt`: `tokenCount` is a candidate when the
    /// `Tok` is plain and is not when it mints a `UUID`. `links` are `(link, destination)` pairs.
    static func expectTokenCountRefutes(
        tokAt tokPath: String,
        files: [String: String],
        links: [(link: String, destination: String)] = [],
        subject: String = tokenCount,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let refuting = "import Foundation\npublic struct Tok { public let id = UUID(); public let n: Int; "
            + "public init(n: Int) { self.n = n } }\n"
        let plain = "public struct Tok { public let n: Int; public init(n: Int) { self.n = n } }\n"
        var found: [String: Set<String>] = [:]
        for (name, tok) in [("refuting", refuting), ("plain", plain)] {
            var project = files
            project["Sources/App/App.swift"] = subject
            project[tokPath] = tok
            let root = try PackagePurityFixtures.makeProject(project)
            defer { try? FileManager.default.removeItem(atPath: root) }
            for link in links {
                try PackagePurityFixtures.symlink(link.link, to: link.destination, in: root)
            }
            found[name] = await PackagePurityFixtures.candidateSymbols(at: root)
        }
        #expect(found["plain"]?.contains("tokenCount") == true, "control lost the subject",
                sourceLocation: sourceLocation)
        #expect(found["refuting"]?.contains("tokenCount") == false, "Tok left the table",
                sourceLocation: sourceLocation)
    }

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

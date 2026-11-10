@testable import Core
import Foundation
import Testing

extension PackagePurityManifestTests {
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
            "Packages/A/Package.swift": Self.libraryManifest("A"),
        ])
    }

    @Test("s6c: the same dependency in Package.swift is compiled")
    func plainManifestDependency() async throws {
        try await Self.expectTokenCountRefutes(tokAt: "Packages/A/Sources/A/Tok.swift", files: [
            "Package.swift": Self.dependsOnA,
            "Packages/A/Package.swift": Self.libraryManifest("A"),
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
            "Core/Package.swift": Self.libraryManifest("Core"),
        ], subject: Self.app(importing: "Core"))
    }

    @Test("f11: a target whose path holds a nested package compiles that package's files")
    func targetPathOverNestedPackage() async throws {
        // `swift build` compiles `Packages/A/Sources/A` into `All`, excluding only A's manifest. The
        // bound looked for a package holding `Packages` and found none.
        try await Self.expectTokenCountRefutes(tokAt: "Packages/A/Sources/A/Tok.swift", files: [
            "Package.swift": """
            // swift-tools-version:5.9
            import PackageDescription
            let package = Package(name: "R", targets: [
                .target(name: "All", path: "Packages", exclude: ["A/Package.swift"])
            ])
            """,
            "Packages/A/Package.swift": Self.libraryManifest("A"),
            "Packages/Loose/L.swift": "struct Loose { let n: Int }\n",
        ], subject: Self.app(importing: "All"))
    }

    @Test("a root target at the root itself compiles every nested package's files")
    func rootTargetAtTheRootReachesEveryPackage() async throws {
        // `path: "."` resolves to the root, `""`, which no `hasPrefix` matched: `Packages/A`, which
        // the root names nowhere else, left the table, though that target's sources include it.
        try await Self.expectTokenCountRefutes(tokAt: "Packages/A/Sources/A/Tok.swift", files: [
            "Package.swift": "// swift-tools-version:5.9\nimport PackageDescription\n"
                + #"let package = Package(name: "R", targets: [.target(name: "App", path: ".")])"#,
            "Packages/A/Package.swift": Self.libraryManifest("A"),
        ], subject: Self.app(importing: "A"))
    }

    @Test("s11: a dependency through a link reaches the walked package the link points to")
    func dependencyThroughALinkedDirectory() async throws {
        // `Packages/Core` links to `Vendor/Core`. The walk does not follow a linked directory, so
        // the package it finds is `Vendor/Core`; matched by spelling, `Packages/Core` named none.
        try await Self.expectTokenCountRefutes(
            tokAt: "Vendor/Core/Sources/Core/Tok.swift",
            files: [
                "Package.swift": Self.dependsOnCore(spelled: "Packages/Core"),
                "Vendor/Core/Package.swift": Self.libraryManifest("Core"),
            ],
            links: [(link: "Packages/Core", destination: "../Vendor/Core")],
            subject: Self.app(importing: "Core")
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
                "Packages/Core/Package.swift": Self.libraryManifest("Core"),
            ],
            subject: Self.app(importing: "Core")
        )
    }

    // MARK: - Fixtures

    /// The critic's subject, `Sources/App/App.swift`, importing the module that declares `Tok`.
    static func app(importing module: String) -> String {
        """
        import \(module)
        public func tokenCount(_ n: Int) -> Int {
            Tok(n: n).n * 2
        }
        """
    }

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
        let otherCase = probe.deletingLastPathComponent().appendingPathComponent(probe.lastPathComponent.uppercased())
        return FileManager.default.fileExists(atPath: otherCase.path)
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
        subject: String = app(importing: "A"),
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

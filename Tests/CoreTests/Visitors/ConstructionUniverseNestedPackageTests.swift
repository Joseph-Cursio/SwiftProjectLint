import Foundation
@testable import SwiftProjectLintVisitors
import Testing

/// Which nested packages the universe takes: those the root compiles — the shared spec's
/// amendment B. The spec's own manifest cases are in `Docs/construction-universe-cases.json`, which
/// `ConstructionUniverseTests` asserts and SwiftInferProperties asserts too; these add whole
/// manifests and computed paths, then pin the closure, the doubt rule and which package a file
/// belongs to.
@Suite("The construction universe's nested-package bound")
struct ConstructionUniverseNestedPackageTests {

    // MARK: - Reading a manifest

    @Test("a whole manifest: literals in source order, comments and other paths ignored")
    func wholeManifest() {
        let manifest = """
        // swift-tools-version:6.2
        import PackageDescription

        // .package(path: "Retired"),
        let package = Package(
            name: "App",
            dependencies: [
                .package(path: "Packages/Models"),
                .package(url: "https://github.com/x/y.git", from: "1.0.0"),
                Package.Dependency.package(name: "Engine", path: "./Packages/Engine/")
            ],
            targets: [
                .executableTarget(name: "App", dependencies: ["Models"], path: "Sources/App"),
                .testTarget(name: "AppTests", path: "Tests/AppTests")
            ]
        )
        """
        #expect(ConstructionUniverse.localPackageDependencies(manifest: manifest) == [
            "Packages/Models", "./Packages/Engine/"
        ])
    }

    @Test("an interpolated or computed path is doubt", arguments: [
        #".package(path: "\(root)/Core")"#,
        ".package(path: localPath)",
        #".package(name: "Core", path: ("Core"))"#
    ])
    func computedPathIsDoubt(manifest: String) {
        #expect(ConstructionUniverse.localPackageDependencies(manifest: manifest) == nil)
    }

    // MARK: - What a manifest is

    @Test("a tools-version comment where SwiftPM looks for one makes a manifest", arguments: [
        "// swift-tools-version:6.2\nimport PackageDescription\n",
        "//swift-tools-version:5.9",
        "  \t// swift-tools-version: 6.0\n",
        "\u{FEFF}// swift-tools-version:6.0\n",
        "// swift-tools-version:5.9\r\nimport PackageDescription\r\n",
        // Blank lines first: SwiftPM loads these (empty ones at any version, whitespace and CRLF
        // ones from 5.4), and a first-line test did not.
        "\n// swift-tools-version:6.0\n",
        "\n\n// swift-tools-version:5.9\nimport PackageDescription\n",
        "\r\n// swift-tools-version:5.9\n",
        // The label in any case, and any horizontal whitespace around the marker.
        "// Swift-Tools-Version: 5.9\n",
        "//\u{00A0}swift-tools-version:5.9\n",
        "\u{00A0}\n// swift-tools-version:5.9\n",
        // From 6.0, below other lines.
        "import PackageDescription\n// swift-tools-version:6.0\n",
        "// Licensed under Apache 2.0\n//\n// swift-tools-version:6.2\n"
    ])
    func toolsVersionLineIsAManifest(text: String) {
        #expect(ConstructionUniverse.isManifest(text))
    }

    @Test("a file without one is a source file, however it is named", arguments: [
        "struct Package: Equatable { let name: String }\n",
        // Below 6.0, SwiftPM wants the comment first.
        "import PackageDescription\n// swift-tools-version:5.9\n",
        "/* swift-tools-version:6.0 */\n",
        "/// swift-tools-version:6.0\n",
        "  \n\t\n",
        ""
    ])
    func noToolsVersionLineIsNoManifest(text: String) {
        #expect(ConstructionUniverse.isManifest(text) == false)
    }

    @Test("only a readable or unreadable regular file named Package.swift is a manifest")
    func manifestOnDisk() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConstructionUniverseManifest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func directory(_ name: String) throws -> String {
            let url = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url.path
        }
        let manifest = "// swift-tools-version:6.0\nimport PackageDescription\n"

        let real = try directory("Real")
        try manifest.write(toFile: real + "/Package.swift", atomically: true, encoding: .utf8)
        let source = try directory("Source")
        try "struct Package { let name: String }\n"
            .write(toFile: source + "/Package.swift", atomically: true, encoding: .utf8)
        let nested = try directory("Nested")
        _ = try directory("Nested/Package.swift")
        let dangling = try directory("Dangling")
        try FileManager.default.createSymbolicLink(
            atPath: dangling + "/Package.swift", withDestinationPath: "/nonexistent/Package.swift"
        )
        let linked = try directory("Linked")
        try FileManager.default.createSymbolicLink(
            atPath: linked + "/Package.swift", withDestinationPath: real + "/Package.swift"
        )
        let empty = try directory("Empty")

        #expect(ConstructionUniverse.manifest(inDirectory: real) == .text(manifest))
        #expect(ConstructionUniverse.manifest(inDirectory: linked) == .text(manifest))
        #expect(ConstructionUniverse.manifest(inDirectory: source) == .absent)
        #expect(ConstructionUniverse.manifest(inDirectory: nested) == .absent)
        #expect(ConstructionUniverse.manifest(inDirectory: dangling) == .absent)
        #expect(ConstructionUniverse.manifest(inDirectory: empty) == .absent)

        let locked = try directory("Locked")
        try manifest.write(toFile: locked + "/Package.swift", atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked + "/Package.swift")
        try #require(FileManager.default.isReadableFile(atPath: locked + "/Package.swift") == false, "running as root?")
        #expect(ConstructionUniverse.manifest(inDirectory: locked) == .unreadable)

        // Beside `Package.swift`, each `Package@swift-*.swift`, read the same way, in name order.
        let versioned = "// swift-tools-version:6.0\nlet package = Package(name: \"V\")\n"
        try versioned.write(toFile: real + "/Package@swift-6.0.swift", atomically: true, encoding: .utf8)
        try "struct NotAManifest {}\n"
            .write(toFile: real + "/Package@swift-5.9.swift", atomically: true, encoding: .utf8)
        try versioned.write(toFile: source + "/Package@swift-6.0.swift", atomically: true, encoding: .utf8)
        #expect(ConstructionUniverse.manifests(inDirectory: real) == [.text(manifest), .absent, .text(versioned)])
        #expect(ConstructionUniverse.manifests(inDirectory: source) == [.absent, .text(versioned)])
        #expect(ConstructionUniverse.manifests(inDirectory: empty) == [.absent])
    }

    // MARK: - The closure

    private static let packages: Set<String> = ["Packages/A", "Packages/B", "Packages/C", "Demo", "Vendor/Lib"]

    private static func compiled(
        _ manifests: [String: String],
        versioned: [String: [String]] = [:],
        unreadable: Set<String> = [],
        reported: Set<String> = [],
        rootHasManifest: Bool = true
    ) -> Set<String> {
        ConstructionUniverse.compiledNestedPackages(
            packages,
            reported: reported,
            rootHasManifest: rootHasManifest,
            rootPath: "/work/App",
            resolvingSymlinks: { $0 },
            manifests: reading(manifests, versioned: versioned, unreadable: unreadable)
        )
    }

    /// A directory's `Package.swift` from `manifests` — `.unreadable` for one in `unreadable`,
    /// `.absent` for any other — then its `versioned` manifests' texts.
    private static func reading(
        _ manifests: [String: String], versioned: [String: [String]] = [:], unreadable: Set<String> = []
    ) -> (String) -> [ConstructionUniverse.Manifest] {
        { directory in
            let primary: ConstructionUniverse.Manifest = unreadable.contains(directory)
                ? .unreadable
                : manifests[directory].map(ConstructionUniverse.Manifest.text) ?? .absent
            return [primary] + (versioned[directory] ?? []).map(ConstructionUniverse.Manifest.text)
        }
    }

    @Test("the root's local path dependencies, followed transitively")
    func transitiveClosure() {
        let reached = Self.compiled([
            "": #".package(path: "Packages/A")"#,
            "Packages/A": #".package(path: "../B")"#,
            "Packages/B": #".package(url: "https://x/y.git", from: "1.0.0")"#,
            "Packages/C": #".package(path: "../../Demo")"#
        ])
        // C depends on Demo, but nothing the root compiles depends on C.
        #expect(reached == ["Packages/A", "Packages/B"])
    }

    @Test("a directory's version-specific manifests add their dependencies, and their doubt")
    func versionSpecificManifestsAreUnioned() {
        // `Package.swift` names nothing; `Package@swift-6.0.swift`, which a 6.x toolchain builds
        // with, names `Packages/A`.
        let manifests = ["": "", "Packages/A": ""]
        let toA = #".package(path: "Packages/A")"#
        #expect(Self.compiled(manifests).isEmpty)
        #expect(Self.compiled(manifests, versioned: ["": [toA]]) == ["Packages/A"])
        #expect(Self.compiled(manifests, versioned: ["": [toA], "Packages/A": [".package(path: p)"]]) == Self.packages)
    }

    @Test("a nested package holding a closure manifest's target path, or under it, is in, with its own closure")
    func targetPathReachesItsPackage() {
        // `Vendor/Lib` holds the root's `Lib` sources, and its closure brings `Demo`.
        #expect(Self.compiled([
            "": #"[.target(name: "Lib", path: "Vendor/Lib/Sources/Lib")]"#,
            "Vendor/Lib": #".package(path: "../../Demo")"#,
            "Demo": ""
        ]) == ["Vendor/Lib", "Demo"])
        // `Packages` lies in no package but holds three, and SwiftPM compiles their sources into
        // `All` (amendment T); `Packages/C`'s closure brings `Demo`. Not `Vendor/Lib`.
        #expect(Self.compiled([
            "": #"[.target(name: "All", path: "Packages")]"#,
            "Packages/C": #".package(path: "../../Demo")"#
        ]) == ["Packages/A", "Packages/B", "Packages/C", "Demo"])
        // A path is matched by component: `Pack` holds nothing.
        #expect(Self.compiled(["": #".target(name: "X", path: "Pack")"#]).isEmpty)
        // The root's `path: "."` resolves to the root, `""`, and holds every package.
        #expect(Self.compiled(["": #".target(name: "App", path: ".")"#]) == Self.packages)
        // A nested package's `path: "."` holds itself and the packages under it, and no other.
        let nested = ConstructionUniverse.compiledNestedPackages(
            ["A", "A/B", "C"],
            reported: [],
            rootHasManifest: true,
            rootPath: "/work/App",
            resolvingSymlinks: { $0 },
            manifests: Self.reading(["": #".package(path: "A")"#, "A": #".target(name: "A", path: ".")"#])
        )
        #expect(nested == ["A", "A/B"])
        // A target path that is not a literal is doubt.
        #expect(Self.compiled(["": #".target(name: "X", path: base + "/X")"#]) == Self.packages)
    }

    @Test("a package the run reports on is in, with its own closure")
    func reportedPackageIsInWithItsClosure() {
        let manifests = [
            "": #".package(path: "Packages/A")"#,
            "Packages/A": "",
            "Packages/C": #".package(path: "../../Demo")"#,
            "Demo": ""
        ]
        #expect(Self.compiled(manifests) == ["Packages/A"])
        // Reporting on `Packages/C` brings it in, and `Demo`, which it depends on; not `Packages/B`.
        #expect(Self.compiled(manifests, reported: ["Packages/C"]) == ["Packages/A", "Packages/C", "Demo"])
        // Its doubt is doubt for the run.
        #expect(Self.compiled(manifests, unreadable: ["Packages/C"], reported: ["Packages/C"]) == Self.packages)
    }

    @Test("a dependency the walk never reached is still followed, by its path")
    func unwalkedDependencyIsFollowed() {
        // `Tests/Support` and `.tools/Gen` are not among the walk's packages — pruned or hidden —
        // but the root compiles them, and so what they depend on.
        let reached = Self.compiled([
            "": #"[.package(path: "Tests/Support"), .package(path: ".tools/Gen")]"#,
            "Tests/Support": #".package(path: "../../Packages/B")"#,
            ".tools/Gen": #".package(path: "../../Demo")"#
        ])
        #expect(reached == ["Packages/B", "Demo"])

        // With nothing there to read, it passes nothing on, and is no doubt; unreadable, it is.
        #expect(Self.compiled(["": #".package(path: "Missing")"#]).isEmpty)
        #expect(Self.compiled(["": #".package(path: ".tools/Gen")"#], unreadable: [".tools/Gen"]) == Self.packages)
    }

    @Test("paths are standardised as absolute paths and kept only under the root")
    func pathsAreStandardisedAgainstTheRoot() {
        let reached = Self.compiled([
            "": """
            let dependencies: [Package.Dependency] = [
                .package(path: "/work/App/Vendor/./Lib"),
                .package(path: "/elsewhere/Demo"),
                .package(path: "../Outside"),
                .package(path: "../App/Demo"),
                .package(path: "./Packages/A/../C/")
            ]
            """,
            "Vendor/Lib": "", "Demo": "", "Packages/C": ""
        ])
        // `../App/Demo` climbs out and back in: it names `/work/App/Demo`, which is under the root.
        #expect(reached == ["Vendor/Lib", "Demo", "Packages/C"])
    }

    @Test("a dependency matches a package where both resolve, however either is spelled")
    func dependenciesMatchByResolvedLocation() {
        // `/alias` links to `/work`, as `/tmp` does to `/private/tmp`: one directory, two spellings.
        // SwiftProjectLint passes a resolved root and SwiftInferProperties the one it was given, so
        // the match must hold for a root spelled either way.
        let resolve: (String) -> String = { path in
            path.hasPrefix("/alias/") ? "/work/" + path.dropFirst("/alias/".count) : path
        }
        let manifests = [
            "": #".package(path: "/alias/App/Vendor/Lib")"#,
            "Vendor/Lib": #"[.package(path: "/work/App/Demo"), .package(path: "/alias/Other/Lib")]"#,
            "Demo": ""
        ]
        for rootPath in ["/work/App", "/alias/App"] {
            let reached = ConstructionUniverse.compiledNestedPackages(
                Self.packages,
                reported: [],
                rootHasManifest: true,
                rootPath: rootPath,
                resolvingSymlinks: resolve,
                manifests: Self.reading(manifests)
            )
            #expect(reached == ["Vendor/Lib", "Demo"], "root spelled \(rootPath)")
        }
    }

    @Test("doubt anywhere in the closure includes every nested package")
    func doubtIncludesAll() {
        let computed = Self.compiled([
            "": #".package(path: "Packages/A")"#,
            "Packages/A": ".package(path: siblingPath)"
        ])
        #expect(computed == Self.packages)

        // A manifest the closure reaches but cannot read is doubt too.
        let unreadable = Self.compiled(["": #".package(path: "Packages/A")"#], unreadable: ["Packages/A"])
        #expect(unreadable == Self.packages)

        // Doubt outside the closure is not: nothing the root compiles reads that manifest.
        let unreached = Self.compiled([
            "": #".package(path: "Packages/A")"#, "Packages/A": "", "Demo": ".package(path: p)"
        ])
        #expect(unreached == ["Packages/A"])
    }

    @Test("a root with no manifest includes every nested package")
    func noRootManifestIncludesAll() {
        #expect(Self.compiled([:], rootHasManifest: false) == Self.packages)
    }

    // MARK: - Which package a file belongs to

    @Test("a file belongs to the nearest package above it, or to the root's own")
    func nearestPackageWins() {
        let packages: Set<String> = ["A", "A/B"]
        #expect(ConstructionUniverse.owningPackage(of: "A/B/Sources/X.swift", among: packages) == "A/B")
        #expect(ConstructionUniverse.owningPackage(of: "A/Sources/X.swift", among: packages) == "A")
        #expect(ConstructionUniverse.owningPackage(of: "AB/Sources/X.swift", among: packages) == nil)
        #expect(ConstructionUniverse.owningPackage(of: "Sources/X.swift", among: packages) == nil)
        #expect(ConstructionUniverse.owningPackage(of: "A", among: packages) == nil)
    }
}

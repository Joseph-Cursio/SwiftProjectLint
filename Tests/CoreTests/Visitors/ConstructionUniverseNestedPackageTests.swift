import Foundation
import SwiftProjectLintVisitors
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
        #".package(name: "Core", path: ("Core"))"#,
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
        "// Licensed under Apache 2.0\n//\n// swift-tools-version:6.2\n",
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
        "",
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
}

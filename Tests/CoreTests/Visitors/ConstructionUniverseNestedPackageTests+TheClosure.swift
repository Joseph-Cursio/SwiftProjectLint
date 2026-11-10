import Foundation
@testable import SwiftProjectLintVisitors
import Testing

extension ConstructionUniverseNestedPackageTests {
    // MARK: - The closure

    static let packages: Set<String> = ["Packages/A", "Packages/B", "Packages/C", "Demo", "Vendor/Lib"]

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
            in: ConstructionUniverse.PackageTree(
                rootPath: "/work/App",
                resolvingSymlinks: { $0 },
                manifests: reading(manifests, versioned: versioned, unreadable: unreadable)
            )
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
            "Packages/C": #".package(path: "../../Demo")"#,
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
            "Demo": "",
        ]) == ["Vendor/Lib", "Demo"])
        // `Packages` lies in no package but holds three, and SwiftPM compiles their sources into
        // `All` (amendment T); `Packages/C`'s closure brings `Demo`. Not `Vendor/Lib`.
        #expect(Self.compiled([
            "": #"[.target(name: "All", path: "Packages")]"#,
            "Packages/C": #".package(path: "../../Demo")"#,
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
            in: ConstructionUniverse.PackageTree(
                rootPath: "/work/App",
                resolvingSymlinks: { $0 },
                manifests: Self.reading(["": #".package(path: "A")"#, "A": #".target(name: "A", path: ".")"#])
            )
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
            "Demo": "",
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
            ".tools/Gen": #".package(path: "../../Demo")"#,
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
            "Vendor/Lib": "", "Demo": "", "Packages/C": "",
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
            "Demo": "",
        ]
        for rootPath in ["/work/App", "/alias/App"] {
            let reached = ConstructionUniverse.compiledNestedPackages(
                Self.packages,
                reported: [],
                rootHasManifest: true,
                in: ConstructionUniverse.PackageTree(
                    rootPath: rootPath,
                    resolvingSymlinks: resolve,
                    manifests: Self.reading(manifests)
                )
            )
            #expect(reached == ["Vendor/Lib", "Demo"], "root spelled \(rootPath)")
        }
    }

    @Test("doubt anywhere in the closure includes every nested package")
    func doubtIncludesAll() {
        let computed = Self.compiled([
            "": #".package(path: "Packages/A")"#,
            "Packages/A": ".package(path: siblingPath)",
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
        let nested: Set<String> = ["A", "A/B"]
        #expect(ConstructionUniverse.owningPackage(of: "A/B/Sources/X.swift", among: nested) == "A/B")
        #expect(ConstructionUniverse.owningPackage(of: "A/Sources/X.swift", among: nested) == "A")
        #expect(ConstructionUniverse.owningPackage(of: "AB/Sources/X.swift", among: nested) == nil)
        #expect(ConstructionUniverse.owningPackage(of: "Sources/X.swift", among: nested) == nil)
        #expect(ConstructionUniverse.owningPackage(of: "A", among: nested) == nil)
    }
}

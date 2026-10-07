@testable import Core
import Foundation
import Testing

/// Which files the package purity is built from, and in what order — checked through
/// `ProjectLinter`, where the reporting filters that must NOT shrink it are applied.
///
/// The universe ignores every reporting filter (`excluded_paths`, the nested-package setting, the
/// generated-file filter) because what is reported says nothing about what is compiled; it drops
/// test targets because a test's namesake is not what production constructs; and it is sorted,
/// because SEI's table depends on input order. See `ConstructionUniverse`. Each test pairs a
/// refuting fixture with a control or carries a sentinel, so neither direction passes vacuously.
@Suite("The package purity's universe, through ProjectLinter")
struct PackagePurityUniverseTests {

    @Test("a refuting namesake declared only in a test target does not refute production")
    func testNamesakeDoesNotRefuteProduction() async throws {
        // `Stamp` is the in-run proof that the facts are live: production, refuting, and its
        // subject withdrawn. Without it, an unwired run would pass this test by refuting nothing.
        let stamp = """
        import Foundation

        struct Stamp: Equatable {
            let at = Date()
            let n: Int
        }

        func stampCount(_ n: Int) -> Int { Stamp(n: n).n }
        """
        let found = try await PackagePurityFixtures.candidates(in: [
            "Sources/Lib/Item.swift": PackagePurityFixtures.plainItem,
            "Sources/Lib/Callers.swift": PackagePurityFixtures.callers,
            "Sources/Lib/Stamp.swift": stamp,
            "Tests/LibTests/ItemFixture.swift": PackagePurityFixtures.refutingItem
        ])
        #expect(found.contains("stampCount") == false, "the facts are not live in this run")
        #expect(found.contains("countOf"))
        #expect(found.contains("viaJoin"))
    }

    @Test("a nested package's types are evidence even when nested packages are not reported")
    func nestedPackageTypesAreEvidence() async throws {
        // The root depends on `Core`, so it compiles it: only then is a nested package in the
        // universe (`PackagePurityNestedPackageTests` pins the bound).
        let manifest = """
        // swift-tools-version:6.2
        import PackageDescription
        let package = Package(name: "App", dependencies: [.package(path: "Core")])
        """
        let refuting = try await PackagePurityFixtures.candidates(in: [
            "Package.swift": manifest,
            "Core/Package.swift": "// swift-tools-version:6.2\n",
            "Core/Sources/Core/Item.swift": PackagePurityFixtures.refutingItem,
            "Sources/App/Callers.swift": PackagePurityFixtures.callers
        ])
        let control = try await PackagePurityFixtures.candidates(in: [
            "Package.swift": manifest,
            "Core/Package.swift": "// swift-tools-version:6.2\n",
            "Core/Sources/Core/Item.swift": PackagePurityFixtures.plainItem,
            "Sources/App/Callers.swift": PackagePurityFixtures.callers
        ])
        #expect(control.contains("countOf"))
        #expect(refuting.contains("sentinelAdd"))
        #expect(refuting.contains("countOf") == false)
    }

    // The next two run with nested packages reported and not: each setting builds the universe
    // from a different walk — the exclusion-free one, or a reuse of what the run already walked —
    // and a reuse that took the *reportable* list would drop exactly these files.

    @Test("a file excluded from reporting is evidence", arguments: [false, true])
    func excludedPathIsEvidence(includeNestedPackages: Bool) async throws {
        // `itemID` returns `String`, so the assertable-return gate cannot hide the effect the way
        // it hides a subject returning `Item` — whose `Equatable` conformance lives in the
        // excluded file, where the pre-scan's conformance index never looks.
        let subjects = """
        func countOf(_ n: Int) -> Int { Item(n: n).n }

        func itemID(_ n: Int) -> String { Item(n: n).id.uuidString }

        func sentinelAdd(_ first: Int, _ second: Int) -> Int { first + second }
        """
        let plainWithID = """
        struct Tag: Equatable {
            var uuidString: String { "tag" }
        }

        struct Item: Equatable {
            let id = Tag()
            let n: Int
        }
        """
        let configuration = LintConfiguration(excludedPaths: ["Vendor/"], includeNestedPackages: includeNestedPackages)
        let refuting = try await PackagePurityFixtures.candidates(
            in: ["Vendor/Item.swift": PackagePurityFixtures.refutingItem, "Sources/Lib/Subjects.swift": subjects],
            configuration: configuration
        )
        let control = try await PackagePurityFixtures.candidates(
            in: ["Vendor/Item.swift": plainWithID, "Sources/Lib/Subjects.swift": subjects],
            configuration: configuration
        )
        #expect(control.isSuperset(of: ["countOf", "itemID"]), "control lost a subject — the fixture is wrong")
        #expect(refuting.contains("sentinelAdd"))
        #expect(refuting.contains("countOf") == false)
        #expect(refuting.contains("itemID") == false)
    }

    @Test("a generated file is evidence", arguments: [false, true])
    func generatedFileIsEvidence(includeNestedPackages: Bool) async throws {
        let header = "// DO NOT EDIT — generated by a tool.\n"
        let configuration = LintConfiguration(includeNestedPackages: includeNestedPackages)
        let refuting = try await PackagePurityFixtures.candidates(in: [
            "Sources/Lib/Item.swift": header + PackagePurityFixtures.refutingItem,
            "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
        ], configuration: configuration)
        let control = try await PackagePurityFixtures.candidates(in: [
            "Sources/Lib/Item.swift": header + PackagePurityFixtures.plainItem,
            "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
        ], configuration: configuration)
        #expect(control.contains("countOf"))
        #expect(refuting.contains("sentinelAdd"))
        #expect(refuting.contains("countOf") == false)
    }

    // The next two need the macOS hidden flag (`chflags hidden`), which Finder sets to hide a file
    // and SwiftPM ignores: a flagged source is compiled. The walk once skipped flagged files with
    // `.skipsHiddenFiles`, so their types left the table; SwiftInferProperties kept them.

    @Test(
        "a file or directory with the macOS hidden flag is in the universe",
        .enabled(if: HiddenFlag.isSupported),
        arguments: ["Sources/Lib/Item.swift", "Sources/Shared"]
    )
    func hiddenFlagIsNoReasonToSkip(flagged: String) async throws {
        let item = flagged.hasSuffix(".swift") ? flagged : flagged + "/Item.swift"
        let root = try PackagePurityFixtures.makeProject([
            item: PackagePurityFixtures.refutingItem,
            "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }
        try #require(HiddenFlag.set(on: root + "/" + flagged))

        #expect(await PackagePurityFixtures.universe(at: root) == [item, "Sources/Lib/Callers.swift"].sorted())
        let found = await PackagePurityFixtures.candidateSymbols(at: root)
        #expect(found.contains("sentinelAdd"))
        #expect(found.contains("countOf") == false, "the flagged \(flagged) left the table")
    }

    @Test("a flagged package in the middle of a dependency chain keeps its files and passes the chain on",
          .enabled(if: HiddenFlag.isSupported))
    func hiddenFlaggedPackageInAChain() async throws {
        let root = try PackagePurityFixtures.makeProject([
            "Package.swift": """
            // swift-tools-version:6.0
            import PackageDescription
            let package = Package(name: "App", dependencies: [.package(path: "Flagged")])
            """,
            "Flagged/Package.swift": """
            // swift-tools-version:6.0
            import PackageDescription
            let package = Package(name: "Flagged", dependencies: [.package(path: "../Next")])
            """,
            "Flagged/Sources/Flagged/Item.swift": PackagePurityFixtures.refutingItem,
            "Next/Package.swift": "// swift-tools-version:6.0\n",
            "Next/Sources/Next/Stamp.swift": "import Foundation\nstruct Stamp { let at = Date(); let n: Int }\n",
            "Sources/App/Callers.swift": PackagePurityFixtures.callers
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }
        try #require(HiddenFlag.set(on: root + "/Flagged"))

        #expect(await PackagePurityFixtures.universe(at: root) == [
            "Flagged/Sources/Flagged/Item.swift", "Next/Sources/Next/Stamp.swift", "Sources/App/Callers.swift"
        ])
    }

    @Test("the witness in a message does not depend on the order discovery returns files in")
    func witnessIndependentOfDiscoveryOrder() async throws {
        // Two declarations of one name, each refuting with its own witness. SEI reports the first
        // in its input order, so the universe has to be sorted for the message to be a function of
        // the project rather than of the file system.
        let path = try PackagePurityFixtures.makeProject([
            "Sources/Lib/A.swift": """
            import Foundation
            #if os(macOS)
            struct Item: Equatable { let id = UUID(); let n: Int }
            #endif
            """,
            "Sources/Lib/B.swift": """
            import Foundation
            #if !os(macOS)
            struct Item: Equatable { let stamp = Date(); let n: Int }
            #endif
            """,
            "Sources/Lib/C.swift": """
            func tally(_ values: [Int]) -> [Int] {
                values.map { value in
                    let item = Item(n: value)
                    let doubled = item.n * 2
                    return doubled + 1
                }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        let files = await FileAnalysisUtils.findSwiftFiles(in: path).sorted()
        var messages: [[String]] = []
        for order in [files, files.reversed()] {
            let linter = ProjectLinter(fileDiscovery: FixedFileDiscovery(files: order)) {
                CrossFileAnalysisEngine(registry: $0)
            }
            let issues = await linter.analyzeProject(
                at: path,
                ruleIdentifiers: [.impureClosureInventory],
                detector: PatternRegistryFactory.createConfiguredSystem().detector
            )
            messages.append(issues.map(\.message))
        }
        #expect(messages[0].count == 1)
        #expect(messages[0] == messages[1])
    }
}

/// macOS's `UF_HIDDEN` file flag — what `chflags hidden` sets — on a fixture file.
enum HiddenFlag {

    /// Sets the flag on `path`, and says whether it is now set.
    static func set(on path: String) -> Bool {
        chflags(path, UInt32(UF_HIDDEN)) == 0 && isSet(on: path)
    }

    static func isSet(on path: String) -> Bool {
        var status = stat()
        return stat(path, &status) == 0 && status.st_flags & UInt32(UF_HIDDEN) != 0
    }

    /// Whether the temporary directory's volume keeps the flag. APFS does; elsewhere the tests that
    /// need it are skipped rather than passed vacuously.
    static let isSupported: Bool = {
        let probe = FileManager.default.temporaryDirectory
            .appendingPathComponent("HiddenFlagProbe-\(UUID().uuidString)").path
        guard FileManager.default.createFile(atPath: probe, contents: Data()) else { return false }
        defer { try? FileManager.default.removeItem(atPath: probe) }
        return set(on: probe)
    }()
}

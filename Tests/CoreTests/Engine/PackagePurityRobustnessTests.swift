@testable import Core
import Foundation
import Testing

/// Files the construction universe must skip or survive. The universe reaches files no run used
/// to read — a nested dependency package, a generated or excluded file — so a file that cannot
/// compile must not feed the table, and one that is merely deep must not take the run down.
@Suite("The package purity skips what cannot compile and survives what is deep")
struct PackagePurityRobustnessTests {

    @Test("a file that is not UTF-8 is not in the universe, though the lenient read decodes it", arguments: [
        (path: "Sources/Lib/Item.generated.swift", excluded: [String]()),   // in the universe only
        (path: "Vendor/Item.swift", excluded: ["Vendor/"])                    // evidence only
    ])
    func nonUTF8FileIsNotInTheUniverse(path: String, excluded: [String]) async throws {
        // `swiftc` rejects a UTF-16 source, so no target compiles this `Item`; SwiftInferProperties
        // skips it too (the shared spec's amendment C). The UTF-8 copy at the same place is the
        // control that the place itself is in the universe.
        let configuration = LintConfiguration(excludedPaths: excluded)
        let utf8 = try await PackagePurityFixtures.candidates(
            in: [path: PackagePurityFixtures.refutingItem, "Sources/Lib/Callers.swift": PackagePurityFixtures.callers],
            configuration: configuration
        )

        let root = try PackagePurityFixtures.makeProject(["Sources/Lib/Callers.swift": PackagePurityFixtures.callers])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let utf16 = try #require(PackagePurityFixtures.refutingItem.data(using: .utf16))
        #expect(utf16.starts(with: [0xFF, 0xFE]) || utf16.starts(with: [0xFE, 0xFF]), "no byte-order mark")
        let file = URL(fileURLWithPath: root).appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try utf16.write(to: file)
        #expect((try? String(contentsOf: file, encoding: .utf8)) == nil)
        #expect(try String(contentsOfFile: file.path).contains("UUID()"), "the lenient read must decode it")

        let found = PackagePurityFixtures.symbols(await ProjectLinter().analyzeProject(
            at: root,
            detector: PatternRegistryFactory.createConfiguredSystem().detector,
            configuration: configuration
        ))
        #expect(utf8.contains("countOf") == false, "control: a UTF-8 Item here refutes — the fixture is wrong")
        #expect(found.contains("sentinelAdd"))
        #expect(found.contains("countOf"), "a UTF-16 file entered the facts")
    }

    // MARK: - Deep trees

    /// A 1,000-arm `else if` chain: the parser recurses once per arm.
    static let elseIfChain = "func classify(_ x: Int) -> Int {\n    if x == 0 { return 0 }\n"
        + (1..<1_000).map { "    else if x == \($0) { return \($0) }\n" }.joined()
        + "    else { return -1 }\n}\n"

    /// A 10,000-link member chain: parsed in a loop, but the facts build walks one frame per link.
    static let memberChain = "struct Link { var b: Link? }\nfunc follow(_ a: Link) -> Any? {\n    return a"
        + String(repeating: ".b", count: 10_000) + "\n}\n"

    /// By name, so a failure prints the shape rather than 20 KB of `.b`.
    static let deepSources = ["else-if chain": elseIfChain, "member chain": memberChain]

    @Test("a deep file in a dependency package does not take the run down", arguments: ["else-if chain", "member chain"])
    func deepDependencyFileIsSurvived(name: String) async throws {
        let source = try #require(Self.deepSources[name])
        // The run never reports on `Sub/`, yet parses it and walks it into the facts. Both used to
        // run on a 512 KB cooperative-pool stack, where each of these overflowed — `SIGBUS`, the
        // whole lint gone, where main had never read the file. The refuting `Item` beside the deep
        // function proves the file reached the facts, so surviving is not skipping.
        let found = try await PackagePurityFixtures.candidates(in: [
            "Package.swift": """
            // swift-tools-version:6.0
            import PackageDescription
            let package = Package(name: "App", dependencies: [.package(path: "Sub")])
            """,
            "Sub/Package.swift": "// swift-tools-version:6.0\n",
            "Sub/Sources/Sub/Deep.swift": PackagePurityFixtures.refutingItem + "\n" + source,
            "Sources/App/Callers.swift": PackagePurityFixtures.callers
        ])
        #expect(found.contains("sentinelAdd"), "\(name): the rule produced nothing")
        #expect(found.contains("countOf") == false, "\(name): the deep file did not reach the facts")
    }
}

@testable import Core
import Foundation
import Testing

/// Files the construction universe must skip or survive. The universe reaches files no run used
/// to read — a nested dependency package, a generated or excluded file — so a file that cannot
/// compile must not feed the table, and one that is merely deep must not take the run down.
@Suite("The package purity skips what cannot compile")
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
}

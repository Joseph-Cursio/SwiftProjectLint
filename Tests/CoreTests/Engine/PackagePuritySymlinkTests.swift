@testable import Core
import Foundation
@testable import SwiftProjectLintEngine
import Testing

/// A symlinked source file is classified **where the link is** — the shared spec's amendment A —
/// and one file on disk is one universe entry.
///
/// SwiftPM compiles `Sources/Lib/Item.swift` into `Lib` whether it is a file or a link to one, so
/// its types belong in the table wherever the target lives. Classifying by the target instead
/// dropped a production type whenever the target sat under a `Tests/` or `*Tests/` folder or a
/// hidden directory, and `countOf` stayed a candidate though the `Item` it builds mints a `UUID`.
/// SwiftInferProperties classifies the walked path, so the two consumers also built different
/// tables. Each test goes through `ProjectLinter` with the `sentinelAdd` sentinel, so an absence
/// proves the facts were live.
@Suite("The package purity classifies a symlink where the link is")
struct PackagePuritySymlinkTests {

    @Test("a link in Sources to a file under the root's Tests/ is compiled where the link is")
    func linkIntoInRootTestsRefutes() async throws {
        let refuting = try await Self.candidates(
            item: PackagePurityFixtures.refutingItem, at: "Tests/Shared/Item.swift",
            linkedAs: "../../Tests/Shared/Item.swift"
        )
        let control = try await Self.candidates(
            item: PackagePurityFixtures.plainItem, at: "Tests/Shared/Item.swift",
            linkedAs: "../../Tests/Shared/Item.swift"
        )
        #expect(control.contains("countOf"), "control lost the subject — the fixture is wrong")
        #expect(refuting.contains("sentinelAdd"), "the rule produced nothing, so the absence proves nothing")
        #expect(refuting.contains("countOf") == false, "the link was classified at its Tests/ target")
    }

    @Test("a link in Sources to a file in a hidden directory is compiled where the link is")
    func linkIntoHiddenDirectoryRefutes() async throws {
        let refuting = try await Self.candidates(
            item: PackagePurityFixtures.refutingItem, at: ".shared/Item.swift",
            linkedAs: "../../.shared/Item.swift"
        )
        #expect(refuting.contains("sentinelAdd"), "the rule produced nothing, so the absence proves nothing")
        #expect(refuting.contains("countOf") == false, "the link was classified at its hidden target")
    }

    @Test("a link to a file outside the root, under a directory named like a test target, refutes")
    func linkOutsideRootIntoTestsNamedDirectoryRefutes() async throws {
        // Outside the root the target's path is absolute, and an absolute path classified by its
        // components would read `SharedTests/` as a test folder — the link's location is the answer.
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackagePurityOutside-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outside) }
        let target = outside.appendingPathComponent("SharedTests/Item.swift").path

        let refuting = try await Self.candidates(
            item: PackagePurityFixtures.refutingItem, at: target, linkedAs: target
        )
        #expect(refuting.contains("sentinelAdd"), "the rule produced nothing, so the absence proves nothing")
        #expect(refuting.contains("countOf") == false, "the link was classified at its outside target")
    }

    @Test("a test folder's link to a production file adds no entry, wherever the folder sorts", arguments: [
        (link: "Tests/LibTests/Item.swift", destination: "../../Sources/Lib/Item.swift"),
        (link: "AppTests/Item.swift", destination: "../Sources/Lib/Item.swift"),
        (link: "ATests/Shared/Item.swift", destination: "../../Sources/Lib/Item.swift")
    ])
    func testTargetLinkToProductionIsOneEntry(link: String, destination: String) async throws {
        let root = try PackagePurityFixtures.makeProject([
            "Sources/Lib/Item.swift": PackagePurityFixtures.refutingItem,
            "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }
        try PackagePurityFixtures.symlink(link, to: destination, in: root)

        // Classified at its target, the link came in as a second `Sources/Lib/Item.swift`. And
        // classify, *then* collapse: collapsed first, `AppTests/Item.swift` — the smaller path —
        // would stand for the file, and then be dropped as a test file, taking `Item` with it.
        let universe = await PackagePurityFixtures.universe(at: root)
        #expect(universe == ["Sources/Lib/Callers.swift", "Sources/Lib/Item.swift"], "link at \(link)")
        let found = await PackagePurityFixtures.candidateSymbols(at: root)
        #expect(found.contains("sentinelAdd"))
        #expect(found.contains("countOf") == false, "link at \(link)")
    }

    @Test("two production paths to one file keep the smaller path, whichever one is the link")
    func duplicateKeepsTheSmallestPath() async throws {
        // Smallest under `String <`, not first-seen: the entry must not depend on walk order, and
        // SwiftInferProperties keeps the same one. The `Lib` pairs are there because APFS lists
        // `Lib` before `B`, so first-seen and smallest disagree on the disk itself.
        let layouts = [
            (file: "Sources/A/Item.swift", link: "Sources/B/Item.swift"),
            (file: "Sources/B/Item.swift", link: "Sources/A/Item.swift"),
            (file: "Sources/B/Item.swift", link: "Sources/Lib/Item.swift"),
            (file: "Sources/Lib/Item.swift", link: "Sources/B/Item.swift")
        ]
        for (file, link) in layouts {
            let root = try PackagePurityFixtures.makeProject([
                file: PackagePurityFixtures.refutingItem,
                "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
            ])
            defer { try? FileManager.default.removeItem(atPath: root) }
            let target = (file as NSString).lastPathComponent
            let directory = ((file as NSString).deletingLastPathComponent as NSString).lastPathComponent
            try PackagePurityFixtures.symlink(link, to: "../\(directory)/\(target)", in: root)

            let universe = await PackagePurityFixtures.universe(at: root)
            #expect(universe == [min(file, link), "Sources/Lib/Callers.swift"], "real file at \(file), link at \(link)")
        }
    }

    @Test("the smaller path wins in either discovery order")
    func duplicateKeepsTheSmallestPathInEitherOrder() async throws {
        // The same rule with the order in hand rather than the file system's: a first-seen dedup
        // keeps `Sources/B/Item.swift` from the second order.
        let root = try PackagePurityFixtures.makeProject([
            "Sources/A/Item.swift": PackagePurityFixtures.refutingItem,
            "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
        ])
        defer { try? FileManager.default.removeItem(atPath: root) }
        try PackagePurityFixtures.symlink("Sources/B/Item.swift", to: "../A/Item.swift", in: root)
        let canonical = ProjectRoot(root).path
        let real = canonical + "/Sources/A/Item.swift"
        let link = canonical + "/Sources/B/Item.swift"
        let callers = canonical + "/Sources/Lib/Callers.swift"

        let shared = await ProjectLinter.parseOnce(
            .init(reportable: [], evidenceOnly: [], constructionUniverse: [real, link, callers]), projectRoot: root
        )
        for order in [[real, link, callers], [link, real, callers]] {
            let kept = ProjectLinter.constructionSources(order, in: shared).map(\.relativePath)
            #expect(kept.sorted() == ["Sources/A/Item.swift", "Sources/Lib/Callers.swift"], "order \(order)")
        }
    }

    @Test("a link into an uncompiled nested package belongs to the package its link sits in")
    func linkIntoUncompiledPackageCountsWhereTheLinkIs() async throws {
        // `Demo/` is a nested package the root does not depend on, so its own files are out; the
        // link `Sources/Lib/Item.swift` is compiled into `Lib`, so it is in. Placed by where it
        // resolves, the link went out with `Demo/`.
        func project(linked: Bool) throws -> String {
            let root = try PackagePurityFixtures.makeProject([
                "Package.swift": PackagePurityManifestTests.rootManifest(dependencies: ""),
                "Demo/Package.swift": "// swift-tools-version:6.0\n",
                "Demo/Sources/Demo/Item.swift": PackagePurityFixtures.refutingItem,
                "Sources/Lib/Callers.swift": PackagePurityFixtures.callers
            ])
            if linked {
                try PackagePurityFixtures.symlink(
                    "Sources/Lib/Item.swift", to: "../../Demo/Sources/Demo/Item.swift", in: root
                )
            }
            return root
        }
        let control = try project(linked: false)
        defer { try? FileManager.default.removeItem(atPath: control) }
        let uncompiled = await PackagePurityFixtures.candidateSymbols(at: control)
        #expect(uncompiled.contains("countOf"), "control: Demo is not compiled")

        let root = try project(linked: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let universe = await PackagePurityFixtures.universe(at: root)
        #expect(universe == ["Sources/Lib/Callers.swift", "Sources/Lib/Item.swift"])
        let found = await PackagePurityFixtures.candidateSymbols(at: root)
        #expect(found.contains("sentinelAdd"))
        #expect(found.contains("countOf") == false, "the link was placed in Demo, where its target is")
    }

    // MARK: - Helpers

    /// The candidates of a project whose `Sources/Lib/Item.swift` is a link to `item`, written at
    /// `target` — a path under the root, or an absolute path outside it. `destination` is the
    /// link's text, resolved from `Sources/Lib/` when relative.
    private static func candidates(
        item: String, at target: String, linkedAs destination: String
    ) async throws -> Set<String> {
        let root = try PackagePurityFixtures.makeProject(["Sources/Lib/Callers.swift": PackagePurityFixtures.callers])
        defer { try? FileManager.default.removeItem(atPath: root) }
        let targetURL = target.hasPrefix("/")
            ? URL(fileURLWithPath: target)
            : URL(fileURLWithPath: root).appendingPathComponent(target)
        try FileManager.default.createDirectory(
            at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try item.write(to: targetURL, atomically: true, encoding: .utf8)
        try PackagePurityFixtures.symlink("Sources/Lib/Item.swift", to: destination, in: root)
        return await PackagePurityFixtures.candidateSymbols(at: root)
    }
}

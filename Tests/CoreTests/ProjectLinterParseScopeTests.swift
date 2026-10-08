@testable import Core
import Foundation
import Testing

/// How many files a run parses: the deterministic stand-in for a wall-clock bound.
///
/// `ProjectLinterTests` used to time `analyzeProject` over a three-file project and expect it to
/// finish in under ten seconds. That measured the machine, not the linter. On 2026-10-07 a full
/// `swift test` beside other builds and fuzzers took 104 s for it, and the same test alone took
/// 0.15 s. What can genuinely make a small run slow is parsing files that are not in it: the
/// regression CLAUDE.md records, where tests pointed the linter at the shared temp directory and
/// it parsed 26,000 files. A count catches that on any machine, under any load.
struct ProjectLinterParseScopeTests {

    /// Every Swift file the fixture holds, relative to its root. One sits a directory down, so
    /// the walk has to recurse to find it.
    private static let fixtureFiles: [(path: String, content: String)] = [
        ("ContentView.swift", """
        import SwiftUI

        struct ContentView: View {
            @State private var counter = 0

            var body: some View {
                Button("Increment") { counter += 1 }
            }
        }
        """),
        ("DetailView.swift", """
        import SwiftUI

        struct DetailView: View {
            let item: Item

            var body: some View {
                Text(item.title)
            }
        }
        """),
        ("Models/Item.swift", """
        struct Item {
            let title: String
        }
        """)
    ]

    /// A run parses each of the project's Swift files once, and nothing else.
    ///
    /// The fixture sits directly under the shared temp directory, which on a working machine
    /// holds tens of thousands of Swift files, so a walk that escaped its root would show up here
    /// as a count rather than a timeout. The raw count also catches one file reached under two
    /// spellings (`/var/…` and `/private/var/…`, say), which `parseOnce`, deduplicating by path,
    /// would parse twice.
    @Test
    func parsesEachProjectFileOnceAndNothingElse() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectLinterParseScopeTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        for file in Self.fixtureFiles {
            let url = directory.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try file.content.write(to: url, atomically: true, encoding: .utf8)
        }

        let discovery = RecordingFileDiscovery()
        let linter = ProjectLinter(fileDiscovery: discovery) { CrossFileAnalysisEngine(registry: $0) }
        _ = await linter.analyzeProject(at: directory.path)

        let parsed = discovery.returnedPaths
        #expect(parsed.count == Self.fixtureFiles.count)
        let expected = Set(Self.fixtureFiles.map {
            directory.appendingPathComponent($0.path).resolvingSymlinksInPath().path
        })
        #expect(Set(parsed.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }) == expected)
    }

    // MARK: - Fakes

    /// The production file discovery, recording every path it hands the linter.
    ///
    /// `ProjectLinter.parseOnce` parses exactly the union of what discovery returns (the
    /// reportable walk, the evidence walk and the construction universe, deduplicated by path),
    /// so this set is the set of files a run parsed.
    private final class RecordingFileDiscovery: FileDiscoveryProtocol, @unchecked Sendable {
        private let production = DefaultFileDiscovery()
        private let lock = NSLock()
        private var returned: Set<String> = []

        var returnedPaths: Set<String> {
            lock.withLock { returned }
        }

        func findSwiftFiles(
            in directory: String,
            excludedPaths: [String],
            excludedFilenames: [String],
            includeNestedPackages: Bool
        ) async -> [String] {
            let paths = await production.findSwiftFiles(
                in: directory,
                excludedPaths: excludedPaths,
                excludedFilenames: excludedFilenames,
                includeNestedPackages: includeNestedPackages
            )
            lock.withLock { returned.formUnion(paths) }
            return paths
        }
    }
}

@testable import Core
import Foundation
import SwiftProjectLintModels
import Testing

/// `excluded_filenames` — a global exclusion matched against a file's basename.
///
/// `excludedPaths` already covers location and, via its `**/` form, name-shaped globs.
/// This exists for a filename that recurs across a tree where the violations are intended
/// wherever it appears, so listing directories would mean enumerating them and revisiting
/// the list whenever one is added.
struct ExcludedFilenamesTests {

    /// A tree with the same filename in two directories, plus one file that should always
    /// be analysed. `Constants.swift` carries a force-unwrap so there is something to find.
    private func makeProject() -> String {
        let root = (FileManager.default.temporaryDirectory.path as NSString)
            .appendingPathComponent("ExcludedFilenames-\(UUID().uuidString)")
        for directory in ["Sources/Alpha", "Sources/Beta"] {
            try? FileManager.default.createDirectory(
                atPath: (root as NSString).appendingPathComponent(directory),
                withIntermediateDirectories: true
            )
        }
        let body = "func boom(_ value: Int?) -> Int { return value! }\n"
        for path in [
            "Sources/Alpha/Constants.swift",
            "Sources/Beta/Constants.swift",
            "Sources/Alpha/Regular.swift"
        ] {
            try? body.write(
                toFile: (root as NSString).appendingPathComponent(path),
                atomically: true, encoding: .utf8
            )
        }
        return root
    }

    private func issues(at root: String, excludedFilenames: [String]) async -> [LintIssue] {
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()
        return await linter.analyzeProject(
            at: root,
            detector: system.detector,
            configuration: LintConfiguration(excludedFilenames: excludedFilenames)
        )
    }

    // MARK: - Discovery

    @Test("an excluded filename is skipped in every directory it appears in")
    func excludedFilenameIsSkippedEverywhere() async {
        let root = makeProject()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let reported = await issues(at: root, excludedFilenames: ["Constants.swift"])

        #expect(reported.contains { $0.filePath.hasSuffix("Constants.swift") } == false)
        // Both copies go, not just the first one found.
        #expect(reported.contains { $0.filePath.contains("Alpha/Constants.swift") } == false)
        #expect(reported.contains { $0.filePath.contains("Beta/Constants.swift") } == false)
    }

    /// Control: without the setting the same tree reports both copies, so the exclusion
    /// above is doing the work rather than the rule being silent on these files.
    @Test("control — without the setting both copies are reported")
    func withoutExclusionBothCopiesAreReported() async {
        let root = makeProject()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let reported = await issues(at: root, excludedFilenames: [])

        #expect(reported.contains { $0.filePath.contains("Alpha/Constants.swift") })
        #expect(reported.contains { $0.filePath.contains("Beta/Constants.swift") })
    }

    @Test("files not named in the setting are still analysed")
    func unlistedFilesAreStillAnalysed() async {
        let root = makeProject()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let reported = await issues(at: root, excludedFilenames: ["Constants.swift"])

        #expect(reported.contains { $0.filePath.hasSuffix("Regular.swift") })
    }

    /// The match is on the basename alone and is exact — a path fragment excludes nothing,
    /// which is what `excludedPaths` is for.
    @Test("matching is exact, not substring")
    func matchingIsExact() async {
        let root = makeProject()
        defer { try? FileManager.default.removeItem(atPath: root) }

        let byFragment = await issues(at: root, excludedFilenames: ["Constants"])
        let byPath = await issues(at: root, excludedFilenames: ["Sources/Alpha/Constants.swift"])

        #expect(byFragment.contains { $0.filePath.hasSuffix("Constants.swift") })
        #expect(byPath.contains { $0.filePath.hasSuffix("Constants.swift") })
    }

    // MARK: - Configuration plumbing

    /// Every rebuild of a configuration has to carry this field. `resolveConfiguration`
    /// reconstructs the whole value for Swift packages, and dropping a field there once
    /// made `--include-nested-packages` a silent no-op for every package project.
    ///
    /// Asserted through `analyzeProject` on a tree with a `Package.swift` — the branch
    /// that triggers the rebuild — rather than by calling the rebuild directly, which is
    /// internal to the engine package. A dropped field shows up here as the excluded file
    /// coming back.
    @Test("the setting survives the Swift-package configuration rebuild")
    func settingSurvivesResolveConfiguration() async {
        let root = makeProject()
        defer { try? FileManager.default.removeItem(atPath: root) }
        try? "// swift-tools-version:6.0\n".write(
            toFile: (root as NSString).appendingPathComponent("Package.swift"),
            atomically: true, encoding: .utf8
        )

        let reported = await issues(at: root, excludedFilenames: ["Constants.swift"])

        #expect(reported.contains { $0.filePath.hasSuffix("Constants.swift") } == false)
        // The rebuild ran and the tree is otherwise analysed, so the absence above is the
        // exclusion surviving rather than the whole run coming back empty.
        #expect(reported.contains { $0.filePath.hasSuffix("Regular.swift") })
    }

    @Test("the setting survives withIncludeNestedPackages")
    func settingSurvivesNestedPackageOverride() {
        let configuration = LintConfiguration(excludedFilenames: ["Constants.swift"])
            .withIncludeNestedPackages(true)

        #expect(configuration.excludedFilenames == ["Constants.swift"])
        #expect(configuration.includeNestedPackages)
    }

    @Test("excluded_filenames is read from YAML")
    func yamlKeyIsParsed() throws {
        let root = (FileManager.default.temporaryDirectory.path as NSString)
            .appendingPathComponent("ExcludedFilenamesYAML-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let path = (root as NSString).appendingPathComponent(".swiftprojectlint.yml")
        try """
        excluded_filenames:
          - "Deprecations.swift"
          - "Constants.swift"
        """.write(toFile: path, atomically: true, encoding: .utf8)

        let configuration = LintConfigurationLoader.load(from: path)

        #expect(configuration.excludedFilenames == ["Deprecations.swift", "Constants.swift"])
    }

    /// Absent key means no exclusions — and the default must be empty rather than nil-ish,
    /// so an unconfigured project analyses everything.
    @Test("an absent key leaves the list empty")
    func absentKeyLeavesListEmpty() throws {
        let root = (FileManager.default.temporaryDirectory.path as NSString)
            .appendingPathComponent("ExcludedFilenamesEmpty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }

        let path = (root as NSString).appendingPathComponent(".swiftprojectlint.yml")
        try "excluded_paths:\n  - \"Tests/\"\n".write(
            toFile: path, atomically: true, encoding: .utf8
        )

        let configuration = LintConfigurationLoader.load(from: path)

        #expect(configuration.excludedFilenames.isEmpty)
        #expect(configuration.excludedPaths == ["Tests/"])
    }
}

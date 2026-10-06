@testable import Core
import Foundation
@testable import SwiftProjectLintEngine
import Testing

/// What the package-purity wiring suites share: the `Item` fixture pair, the subjects, and a lint
/// through `ProjectLinter` over a scratch project.
///
/// Every lint goes through `PatternRegistryFactory.createConfiguredSystem().detector` rather than
/// the shared registry, which is not safe to configure from parallel tests.
enum PackagePurityFixtures {

    /// The idiom the facts exist for: `let id = UUID()` makes every construction nondeterministic.
    static let refutingItem = """
    import Foundation

    struct Item: Equatable {
        let id = UUID()
        let n: Int
    }
    """

    static let plainItem = """
    struct Item: Equatable {
        let n: Int
    }
    """

    /// One subject per place the oracle is created, each moved by the construction alone.
    static let callers = """
    func countOf(_ n: Int) -> Int { Item(n: n).n }

    func viaJoin(_ n: Int) -> Int { countOf(n) }

    func sentinelAdd(_ first: Int, _ second: Int) -> Int { first + second }

    // A pure namesake, so the one-hop join cannot settle `scaled` and `useBoth` moves through
    // the clean-method catalog alone.
    func scaled(_ value: Double) -> Double { value * 2 }

    struct Calc {
        let base: Int
        var total: Int { Item(n: base).n }
        func scaled(_ n: Int) -> Int { Item(n: n).n * base }
        func plain(_ n: Int) -> Int { n * base }
        func useBoth(_ n: Int) -> Int { scaled(n) + plain(n) }
    }

    struct Gauge {
        let base: Int
        var stamped: Int { Item(n: base).n }
        func reading(_ offset: Int) -> Int { stamped + offset }
    }
    """

    // MARK: - Linting a scratch project

    static func makeProject(_ files: [String: String]) throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackagePurityWiring-\(UUID().uuidString)")
        for (relative, text) in files {
            let url = root.appendingPathComponent(relative)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        return root.path
    }

    static func lint(
        _ files: [String: String],
        ruleIdentifiers: [RuleIdentifier]? = nil,
        configuration: LintConfiguration = .default
    ) async throws -> [LintIssue] {
        let path = try makeProject(files)
        defer { try? FileManager.default.removeItem(atPath: path) }
        return await ProjectLinter().analyzeProject(
            at: path,
            ruleIdentifiers: ruleIdentifiers,
            detector: PatternRegistryFactory.createConfiguredSystem().detector,
            configuration: configuration
        )
    }

    /// The Pure Function Property-Test Candidate symbols a lint of `files` reports.
    static func candidates(
        in files: [String: String],
        configuration: LintConfiguration = .default
    ) async throws -> Set<String> {
        symbols(try await lint(files, configuration: configuration))
    }

    static func candidateSymbols(at path: String) async -> Set<String> {
        symbols(await ProjectLinter().analyzeProject(
            at: path, detector: PatternRegistryFactory.createConfiguredSystem().detector
        ))
    }

    static func symbols(_ issues: [LintIssue]) -> Set<String> {
        Set(issues.filter { $0.ruleName == .pureFunctionCandidate }.compactMap(\.symbol))
    }

    // MARK: - The universe itself

    /// The universe paths a run over `path` builds its table from — discovery and the shared parse
    /// exactly as `analyzeProject` runs them, stopped before the analysis phases.
    static func universe(at path: String, configuration: LintConfiguration = .default) async -> [String] {
        let files = await ProjectLinter().discoverFiles(at: path, configuration: configuration)
        return await ProjectLinter.sharedParse(files, projectRoot: path).purity.universe
    }

    /// Creates a symbolic link at `link` (relative to `root`) whose destination is `destination`,
    /// written as given — relative destinations resolve from the link's own directory.
    static func symlink(_ link: String, to destination: String, in root: String) throws {
        let url = URL(fileURLWithPath: root).appendingPathComponent(link)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
    }
}

/// Returns the same file list, in the given order, for every discovery call.
struct FixedFileDiscovery: FileDiscoveryProtocol {
    let files: [String]

    func findSwiftFiles(
        in _: String, excludedPaths _: [String], excludedFilenames _: [String], includeNestedPackages _: Bool
    ) -> [String] {
        files
    }
}

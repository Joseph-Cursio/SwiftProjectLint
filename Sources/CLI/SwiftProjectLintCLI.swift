import ArgumentParser
import Core
import Foundation

@main
struct SwiftProjectLintCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftprojectlint",
        abstract: "Analyze Swift projects for common issues and anti-patterns.",
        version: "1.0.0"
    )

    @Argument(help: "Path to the Swift project directory to analyze.")
    var projectPath: String

    @Option(
        name: .long,
        help: """
        Output format: text, json, html, csv, or pbt-seeds \
        (emit pure-function candidates as a swift-infer seed manifest).
        """
    )
    var format: OutputFormat = .text

    @Option(name: .long, help: "Minimum severity to trigger a non-zero exit: error, warning, or info.")
    var threshold: SeverityThreshold = .warning

    @Option(name: .long, parsing: .upToNextOption, help: "Pattern categories to analyze (default: all).")
    var categories: [String] = []

    @Option(name: .long, help: "Path to configuration file (default: .swiftprojectlint.yml in project root).")
    var config: String?

    @Flag(
        name: .long,
        help: ArgumentHelp(
            "Analyze nested first-party Swift packages instead of skipping them.",
            discussion: "Directories with their own Package.swift are normally skipped; this keeps "
                + "them in scope so cross-file rules can span the boundary."
        )
    )
    var includeNestedPackages = false

    mutating func run() async throws {
        let resolvedPath = (projectPath as NSString).standardizingPath
        let absolutePath: String
        if resolvedPath.hasPrefix("/") {
            absolutePath = resolvedPath
        } else {
            absolutePath = FileManager.default.currentDirectoryPath + "/" + resolvedPath
        }

        guard FileManager.default.fileExists(atPath: absolutePath) else {
            throw ValidationError("Project path does not exist: \(absolutePath)")
        }

        let selectedCategories = try parseCategories()

        // Load configuration from YAML file
        var configuration: LintConfiguration
        if let configPath = config {
            configuration = LintConfigurationLoader.load(from: configPath)
        } else {
            configuration = LintConfigurationLoader.load(projectRoot: absolutePath)
        }

        // The --include-nested-packages flag can only turn the option on, so it
        // overrides the config when present and leaves it untouched otherwise.
        if includeNestedPackages {
            configuration = configuration.withIncludeNestedPackages(true)
        }

        let system = PatternRegistryFactory.createConfiguredSystem()
        let linter = ProjectLinter()

        let issues = await linter.analyzeProject(
            at: absolutePath,
            categories: selectedCategories,
            detector: system.detector,
            configuration: configuration
        )

        print(format.formatter.format(issues: issues))

        // Surface skipped scope: a clean-looking result is misleading if whole
        // first-party packages were never analyzed. Written to stderr so it never
        // contaminates machine-readable stdout (e.g. `--format json`).
        if configuration.includeNestedPackages == false,
           FileAnalysisUtils.containsNestedPackage(in: absolutePath) {
            Self.printToStandardError(Self.nestedPackagesSkippedNotice)
        }

        // `pbt-seeds` is an extraction format, not a lint gate: it exists to hand a
        // seed manifest to `swift-infer`. Failing the process for findings would make
        // `swiftprojectlint … --format pbt-seeds > .pbt/seeds.json` abort under a
        // `set -e` pipeline, so this format always exits 0.
        guard format != .pbtSeeds else { return }

        let code = ExitCodes.exitCode(for: issues, threshold: threshold)
        if code != 0 {
            throw ExitCode(code)
        }
    }

    /// Shown when a project has nested first-party packages but they were left out
    /// of scope. Cross-file rules can't span the package boundary, so issues inside
    /// those packages go unreported — a "clean" result here doesn't mean clean.
    static let nestedPackagesSkippedNotice =
        "Note: nested Swift packages were not analyzed, so issues inside them are "
        + "not reported. Cross-file rules (e.g. architecture and protocol checks) "
        + "cannot span the package boundary. Re-run with --include-nested-packages "
        + "to include them."

    private static func printToStandardError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    private func parseCategories() throws -> [PatternCategory]? {
        guard !categories.isEmpty else { return nil }

        let categoryMap: [String: PatternCategory] = Dictionary(
            uniqueKeysWithValues: PatternCategory.allCases.map {
                (String(describing: $0), $0)
            }
        )

        var result: [PatternCategory] = []
        for name in categories {
            guard let category = categoryMap[name] else {
                let valid = categoryMap.keys.sorted().joined(separator: ", ")
                throw ValidationError("Unknown category '\(name)'. Valid categories: \(valid)")
            }
            result.append(category)
        }
        return result
    }
}

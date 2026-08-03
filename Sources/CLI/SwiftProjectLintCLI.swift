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

    /// Repeat the flag, or comma-separate: `--categories a,b` / `--categories a --categories b`.
    ///
    /// **`.singleValue` rather than `.upToNextOption`, and the difference is a real defect.**
    /// `.upToNextOption` consumes every following value until the next `-`-prefixed token, which
    /// includes the required `<project-path>` positional when it is written last:
    ///
    /// ```
    /// swiftprojectlint --categories testability /path/to/project   # exit 64
    /// Error: Missing expected argument '<project-path>'
    /// ```
    ///
    /// The path was read as a category name and the positional went missing. The failure is at
    /// least loud — a parse error, not a silent scan of the wrong tree — but it cannot be caught
    /// and explained, because parsing fails before `validate()` ever runs. An unambiguous parsing
    /// strategy is the only structural fix.
    ///
    /// Comma splitting is handled in `parseCategories()` and matches `swift-infer --packs`, so the
    /// two halves of the lint → infer hop accept list arguments the same way.
    ///
    /// This drops the space-separated form (`--categories a b`), which `Docs/reference.md`
    /// documented. Both of that file's examples put the path first and so were never at risk;
    /// they are updated regardless, since the syntax they show no longer parses.
    @Option(
        name: .long,
        parsing: .singleValue,
        help: "Pattern category to analyze; repeat or comma-separate for several (default: all)."
    )
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

        print(Self.render(issues, format: format, selectedCategories: selectedCategories))

        // Surface skipped scope: a clean-looking result is misleading if whole
        // first-party packages were never analyzed. Written to stderr so it never
        // contaminates machine-readable stdout (e.g. `--format json`).
        if configuration.includeNestedPackages == false,
           FileAnalysisUtils.containsNestedPackage(in: absolutePath) {
            Self.printToStandardError(Self.nestedPackagesSkippedNotice)
        }

        // A seed-bearing finding with no resolved symbol cannot become a seed, so the manifest is
        // shorter than the run that produced it — silently, and while still exiting 0. That is the
        // shape of a confident zero, and it has happened: a lossy `LintIssue` rebuild once emptied
        // a whole rule's contribution without a word. Same stderr channel and same reasoning as
        // the skipped-scope notice above — the output understates reality, so say so.
        if format == .pbtSeeds, let dropped = PBTSeedsFormatter.droppedSeeds(in: issues) {
            Self.printToStandardError(dropped.notice)
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

    /// Render the report, collapsing the property-test candidate inventory when a human is reading.
    ///
    /// Only `text` collapses. The machine-readable formats stay complete on purpose: a JSON or CSV
    /// consumer filters for itself and would be poorly served by a tool that decided which findings
    /// it was allowed to see, and `pbt-seeds` exists precisely to carry the candidates.
    ///
    /// Naming `testability` in `--categories` is the opt-in. Asking for the category is asking for
    /// its contents, so the listing comes back in full with no extra flag to discover.
    static func render(
        _ issues: [LintIssue],
        format: OutputFormat,
        selectedCategories: [PatternCategory]?
    ) -> String {
        let requestedTestability = selectedCategories?.contains(.testability) ?? false
        guard format == .text, !requestedTestability else {
            return format.formatter.format(issues: issues)
        }
        let split = CandidateInventory.split(issues, collapsing: true)
        return TextFormatter(withheld: split.withheld).format(issues: split.listed)
    }

    private static func printToStandardError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// Flatten the repeated flag's values, splitting each on commas.
    ///
    /// Empties are dropped so `a,,b` and a trailing `a,` behave, rather than failing with
    /// `Unknown category ''` — a message that names nothing and helps nobody.
    static func expandCategoryNames(_ raw: [String]) -> [String] {
        raw.flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func parseCategories() throws -> [PatternCategory]? {
        let names = Self.expandCategoryNames(categories)
        guard !names.isEmpty else { return nil }

        let categoryMap: [String: PatternCategory] = Dictionary(
            uniqueKeysWithValues: PatternCategory.allCases.map {
                (String(describing: $0), $0)
            }
        )

        var result: [PatternCategory] = []
        for name in names {
            guard let category = categoryMap[name] else {
                let valid = categoryMap.keys.sorted().joined(separator: ", ")
                throw ValidationError("Unknown category '\(name)'. Valid categories: \(valid)")
            }
            result.append(category)
        }
        return result
    }
}

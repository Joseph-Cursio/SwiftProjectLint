import ArgumentParser
import Foundation
import Core

@main
struct SwiftProjectLintCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftprojectlint",
        abstract: "Analyze Swift projects for common issues and anti-patterns.",
        version: "1.0.0"
    )

    @Argument(help: "Path to the Swift project directory to analyze.")
    var projectPath: String

    @Option(name: .long, help: "Output format: text or json.")
    var format: OutputFormat = .text

    @Option(name: .long, help: "Minimum severity to trigger a non-zero exit: error, warning, or info.")
    var threshold: SeverityThreshold = .warning

    @Option(name: .long, parsing: .upToNextOption, help: "Pattern categories to analyze (default: all).")
    var categories: [String] = []

    @Option(name: .long, help: "Path to configuration file (default: .swiftprojectlint.yml in project root).")
    var config: String?

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
        let configuration: LintConfiguration
        if let configPath = config {
            configuration = LintConfigurationLoader.load(from: configPath)
        } else {
            configuration = LintConfigurationLoader.load(projectRoot: absolutePath)
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

        let code = ExitCodes.exitCode(for: issues, threshold: threshold)
        if code != 0 {
            throw ExitCode(code)
        }
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

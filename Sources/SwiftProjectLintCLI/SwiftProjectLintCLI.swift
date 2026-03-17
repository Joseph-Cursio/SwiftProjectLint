import ArgumentParser
import Foundation
import SwiftProjectLintCore

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

    mutating func run() async throws {
        // Stub — will be implemented in next commit
        print("Analyzing \(projectPath)...")
    }
}

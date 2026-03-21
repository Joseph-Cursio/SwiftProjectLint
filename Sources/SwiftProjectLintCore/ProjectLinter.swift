import Foundation
import SwiftParser
import SwiftSyntax

/// Analyzes SwiftUI projects by running per-file pattern detection concurrently,
/// then cross-file analysis sequentially.
///
/// ## Usage Example
/// ```swift
/// let linter = ProjectLinter()
/// let issues = await linter.analyzeProject(at: "/path/to/project")
/// for issue in issues {
///     print(issue.message)
/// }
/// ```
public final class ProjectLinter: Sendable {
    public init() {}

    /// Sets the SwiftSyntax pattern detector to use for analysis.
    /// This allows the ProjectLinter to use a configured detector with registered patterns.
    ///
    /// - Parameter detector: The configured SourcePatternDetector to use.
    public func setDetector(_ detector: SourcePatternDetector) {
        // Create a new linter instance internally — but we need to keep the public API.
        // Since this is called before analyzeProject, store via nonisolated(unsafe).
        detectorOverride = detector
    }

    // nonisolated(unsafe) because setDetector is always called before analyzeProject,
    // never concurrently. This preserves the existing public API.
    nonisolated(unsafe) private var detectorOverride: SourcePatternDetector?

    /// Analyzes a SwiftUI project at the specified file system path.
    ///
    /// Per-file analysis runs concurrently (throttled to CPU count) using a TaskGroup.
    /// Cross-file analysis runs sequentially after all per-file results have been collected.
    ///
    /// - Parameters:
    ///   - path: The root directory path of the SwiftUI project to analyze.
    ///   - categories: Optional array of pattern categories to analyze. If nil, analyzes all categories.
    ///   - ruleIdentifiers: Optional array of specific rule identifiers to analyze. If provided, overrides categories.
    /// - Returns: An array of `LintIssue` objects describing all detected issues.
    public func analyzeProject(
        at path: String,
        categories: [PatternCategory]? = nil,
        ruleIdentifiers: [RuleIdentifier]? = nil,
        configuration: LintConfiguration = .default
    ) async -> [LintIssue] {
        let filePaths = await FileAnalysisUtils.findSwiftFiles(
            in: path, excludedPaths: configuration.excludedPaths
        )

        // Resolve effective rules from configuration + CLI overrides
        let effectiveRules = configuration.resolveRules(
            cliCategories: categories,
            cliRuleIdentifiers: ruleIdentifiers
        )

        // Resolve the registry once so each task can create its own detector
        let detector = detectorOverride ?? SourcePatternDetector()
        let registry = detector.registry

        // Per-file I/O and analysis — throttled to avoid memory exhaustion on large projects.
        let maxConcurrency = max(ProcessInfo.processInfo.activeProcessorCount, 1)
        let perFileResults = await withTaskGroup(
            of: (file: ProjectFile, issues: [LintIssue],
                 parsedAST: SourceFileSyntax)?.self
        ) { group in
            var iterator = filePaths.makeIterator()

            // Seed initial batch
            for _ in 0..<maxConcurrency {
                guard let filePath = iterator.next() else { break }
                group.addTask {
                    Self.analyzeFile(
                        at: filePath, registry: registry,
                        categories: effectiveRules != nil ? nil : categories,
                        ruleIdentifiers: effectiveRules
                    )
                }
            }

            // As each task completes, start the next
            var allFiles: [ProjectFile] = []
            var allIssues: [LintIssue] = []
            var astCache: [String: SourceFileSyntax] = [:]
            for await result in group {
                if let result {
                    allFiles.append(result.file)
                    allIssues.append(contentsOf: result.issues)
                    astCache[result.file.name] = result.parsedAST
                }
                if let filePath = iterator.next() {
                    group.addTask {
                        Self.analyzeFile(
                            at: filePath, registry: registry,
                            categories: effectiveRules != nil ? nil : categories,
                            ruleIdentifiers: effectiveRules
                        )
                    }
                }
            }
            return (allFiles, allIssues, astCache)
        }

        let projectFiles = perFileResults.0
        var issues = perFileResults.1
        let astCache = perFileResults.2

        // Run cross-file pattern detection
        let crossFileEngine = CrossFileAnalysisEngine()
        let crossFilePatternIssues: [LintIssue]
        if let effectiveRules {
            crossFilePatternIssues = crossFileEngine.detectCrossFilePatterns(
                projectFiles: projectFiles,
                ruleIdentifiers: effectiveRules,
                preBuiltCache: astCache
            )
        } else {
            crossFilePatternIssues = crossFileEngine.detectCrossFilePatterns(
                projectFiles: projectFiles,
                categories: categories,
                preBuiltCache: astCache
            )
        }
        issues.append(contentsOf: crossFilePatternIssues)

        // Apply per-rule overrides (severity changes, per-rule path exclusions)
        return configuration.applyOverrides(to: issues, projectRoot: path)
    }

    /// Analyzes a single file — pure function safe for concurrent task group use.
    private static func analyzeFile(
        at filePath: String,
        registry: PatternVisitorRegistry,
        categories: [PatternCategory]?,
        ruleIdentifiers: [RuleIdentifier]?
    ) -> (file: ProjectFile, issues: [LintIssue], parsedAST: SourceFileSyntax)? {
        guard !Task.isCancelled else { return nil }
        guard let content = try? String(contentsOfFile: filePath) else { return nil }

        let file = ProjectFile(
            name: (filePath as NSString).lastPathComponent,
            content: content
        )
        let parsedAST = Parser.parse(source: content)
        let det = SourcePatternDetector(registry: registry)

        let issues: [LintIssue]
        if let ruleIdentifiers {
            issues = det.detectPatterns(
                in: file.content, filePath: file.name,
                ruleIdentifiers: ruleIdentifiers, parsedAST: parsedAST
            )
        } else {
            issues = det.detectPatterns(
                in: file.content, filePath: file.name,
                categories: categories, parsedAST: parsedAST
            )
        }

        return (file: file, issues: issues, parsedAST: parsedAST)
    }
}

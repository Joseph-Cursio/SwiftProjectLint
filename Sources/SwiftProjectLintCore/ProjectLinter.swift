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

    /// Analyzes a SwiftUI project at the specified file system path.
    ///
    /// Per-file analysis runs concurrently (throttled to CPU count) using a TaskGroup.
    /// Cross-file analysis runs sequentially after all per-file results have been collected.
    ///
    /// - Parameters:
    ///   - path: The root directory path of the SwiftUI project to analyze.
    ///   - categories: Optional array of pattern categories to analyze. If nil, analyzes all categories.
    ///   - ruleIdentifiers: Optional array of specific rule identifiers to analyze. If provided, overrides categories.
    ///   - detector: Optional pre-configured detector. If nil, a default detector is created.
    ///   - configuration: YAML-based configuration for rule/path control.
    /// - Returns: An array of `LintIssue` objects describing all detected issues.
    public func analyzeProject(
        at path: String,
        categories: [PatternCategory]? = nil,
        ruleIdentifiers: [RuleIdentifier]? = nil,
        detector: SourcePatternDetector? = nil,
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

        // Pre-scan: collect all type names that conform to Identifiable.
        // This set is passed to per-file visitors so they can suppress
        // false-positive "ForEach without ID" warnings for Identifiable types.
        let identifiableTypes = Self.collectIdentifiableTypes(from: filePaths)

        // Resolve the registry once so each task can create its own detector
        let detector = detector ?? SourcePatternDetector()
        detector.knownIdentifiableTypes = identifiableTypes
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
                        ruleIdentifiers: effectiveRules,
                        identifiableTypes: identifiableTypes
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
                            ruleIdentifiers: effectiveRules,
                            identifiableTypes: identifiableTypes
                        )
                    }
                }
            }
            return (allFiles, allIssues, astCache)
        }

        let projectFiles = perFileResults.0
        var issues = perFileResults.1
        let astCache = perFileResults.2

        // Run cross-file pattern detection (use the same registry as per-file analysis)
        let crossFileEngine = CrossFileAnalysisEngine(registry: registry)
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

    /// Scans all project files and returns the set of type names that conform to `Identifiable`.
    ///
    /// This is a fast, read-only pre-scan that only inspects inheritance clauses.
    /// The result is passed to per-file visitors so they can avoid false-positive
    /// "ForEach without ID" warnings for Identifiable element types.
    private static func collectIdentifiableTypes(from filePaths: [String]) -> Set<String> {
        var allTypes: Set<String> = []
        for filePath in filePaths {
            guard let content = try? String(contentsOfFile: filePath) else { continue }
            let syntax = Parser.parse(source: content)
            let collector = IdentifiableTypeCollector()
            collector.walk(syntax)
            allTypes.formUnion(collector.identifiableTypes)
        }
        return allTypes
    }

    /// Analyzes a single file — pure function safe for concurrent task group use.
    private static func analyzeFile(
        at filePath: String,
        registry: PatternVisitorRegistry,
        categories: [PatternCategory]?,
        ruleIdentifiers: [RuleIdentifier]?,
        identifiableTypes: Set<String> = []
    ) -> (file: ProjectFile, issues: [LintIssue], parsedAST: SourceFileSyntax)? {
        guard !Task.isCancelled else { return nil }
        guard let content = try? String(contentsOfFile: filePath) else { return nil }

        let file = ProjectFile(
            name: (filePath as NSString).lastPathComponent,
            content: content
        )
        let parsedAST = Parser.parse(source: content)
        let det = SourcePatternDetector(registry: registry)
        det.knownIdentifiableTypes = identifiableTypes

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

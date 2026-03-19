import Foundation
import SwiftParser
import SwiftSyntax

/// A class responsible for linting SwiftUI projects by analyzing project files, extracting state variables,
/// building view hierarchies, and detecting various lint issues and patterns across the codebase.
///
/// The `ProjectLinter` traverses Swift source files, identifies property wrappers (such as `@State`,
/// `@StateObject`), builds a map of state usage, and performs analysis to detect cross-file issues
/// like duplicate state variables and cross-file patterns that might require refactoring or improvements.
///
/// - Important: Uses basic file and string matching operations. For comprehensive static analysis,
/// integrating with a Swift parser is recommended.
///
/// ## Usage Example
/// ```swift
/// let linter = ProjectLinter()
/// let issues = await linter.analyzeProject(at: "/path/to/project")
/// for issue in issues {
///     print(issue.message)
/// }
/// ```

public class ProjectLinter {
    private var projectFiles: [ProjectFile] = []
    private var singleFileDetector: SourcePatternDetector?
    private var crossFileDetector: CrossFileAnalysisEngine?

    /// Analyzes a SwiftUI project at the specified file system path, performing static analysis to detect state variable usage,
    /// build view hierarchies, and report lint issues and code patterns across all Swift source files in the project.
    ///
    /// Per-file analysis runs concurrently using a TaskGroup. Cross-file analysis runs sequentially
    /// after all per-file results have been collected.
    ///
    /// - Parameters:
    ///   - path: The root directory path of the SwiftUI project to analyze.
    ///   - categories: Optional array of pattern categories to analyze. If nil, analyzes all categories.
    ///   - ruleIdentifiers: Optional array of specific rule identifiers to analyze. If provided, overrides categories.
    /// - Returns: An array of `LintIssue` objects describing all detected issues, warnings, or suggestions throughout the project.
    public func analyzeProject(
        at path: String,
        categories: [PatternCategory]? = nil,
        ruleIdentifiers: [RuleIdentifier]? = nil
    ) async -> [LintIssue] {
        let filePaths = await FileAnalysisUtils.findSwiftFiles(in: path)

        // Resolve the registry once so each task can create its own detector
        let registry = (singleFileDetector ?? SourcePatternDetector()).registry

        // Bind parameters locally so they can be safely captured by sendable closures
        let taskCategories = categories
        let taskRuleIdentifiers = ruleIdentifiers

        // Per-file I/O and analysis — embarrassingly parallel.
        // Each task reads its own file and runs pattern detection, keeping
        // synchronous file I/O off the caller and spreading it across the pool.
        let perFileResults = await withTaskGroup(
            of: (file: ProjectFile, issues: [LintIssue],
                 parsedAST: SourceFileSyntax)?.self
        ) { group in
            for filePath in filePaths {
                group.addTask {
                    guard !Task.isCancelled else { return nil }
                    guard let content = try? String(contentsOfFile: filePath) else {
                        return nil
                    }
                    let file = ProjectFile(
                        name: (filePath as NSString).lastPathComponent,
                        content: content
                    )

                    // Parse once, reuse for detection and state extraction
                    let parsedAST = Parser.parse(source: content)
                    let detector = SourcePatternDetector(registry: registry)

                    let issues: [LintIssue]
                    if let ruleIdentifiers = taskRuleIdentifiers {
                        issues = detector.detectPatterns(
                            in: file.content,
                            filePath: file.name,
                            ruleIdentifiers: ruleIdentifiers,
                            parsedAST: parsedAST
                        )
                    } else {
                        issues = detector.detectPatterns(
                            in: file.content,
                            filePath: file.name,
                            categories: taskCategories,
                            parsedAST: parsedAST
                        )
                    }

                    return (file: file, issues: issues, parsedAST: parsedAST)
                }
            }

            var allFiles: [ProjectFile] = []
            var allIssues: [LintIssue] = []
            var astCache: [String: SourceFileSyntax] = [:]
            for await result in group {
                guard let result else { continue }
                allFiles.append(result.file)
                allIssues.append(contentsOf: result.issues)
                astCache[result.file.name] = result.parsedAST
            }
            return (allFiles, allIssues, astCache)
        }

        projectFiles = perFileResults.0
        var issues = perFileResults.1
        let astCache = perFileResults.2

        // Run cross-file pattern detection using SwiftSyntax, respecting enabled patterns or categories
        let crossFileDetector = self.crossFileDetector ?? CrossFileAnalysisEngine()
        let crossFilePatternIssues: [LintIssue]
        if let ruleIdentifiers = ruleIdentifiers {
            crossFilePatternIssues = crossFileDetector.detectCrossFilePatterns(
                projectFiles: projectFiles,
                ruleIdentifiers: ruleIdentifiers,
                preBuiltCache: astCache
            )
        } else {
            crossFilePatternIssues = crossFileDetector.detectCrossFilePatterns(
                projectFiles: projectFiles,
                categories: categories,
                preBuiltCache: astCache
            )
        }
        issues.append(contentsOf: crossFilePatternIssues)

        return issues
    }

    public init() {}

    /// Sets the SwiftSyntax pattern detector to use for analysis.
    /// This allows the ProjectLinter to use a configured detector with registered patterns.
    ///
    /// - Parameter detector: The configured SourcePatternDetector to use.
    public func setDetector(_ detector: SourcePatternDetector) {
        self.singleFileDetector = detector
    }
}

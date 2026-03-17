import Foundation
import SwiftParser
import SwiftUI

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
    private var stateVariables: [StateVariable] = []
    private var viewHierarchies: [ViewHierarchy] = []
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
        print("DEBUG: analyzeProject called with path: '\(path)'")
        print(
            "DEBUG: categories: \(categories?.map { String(describing: $0) } ?? ["all"])"
        )
        print(
            "DEBUG: ruleIdentifiers: \(ruleIdentifiers?.map { $0.rawValue } ?? [])"
        )

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
            of: (file: ProjectFile, issues: [LintIssue], stateVars: [StateVariable])?.self
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

                    let detector = SourcePatternDetector(registry: registry)

                    let issues: [LintIssue]
                    if let ruleIdentifiers = taskRuleIdentifiers {
                        issues = detector.detectPatterns(
                            in: file.content,
                            filePath: file.name,
                            ruleIdentifiers: ruleIdentifiers
                        )
                    } else {
                        issues = detector.detectPatterns(
                            in: file.content,
                            filePath: file.name,
                            categories: taskCategories
                        )
                    }

                    let stateVars = ProjectLinter.extractStateVariables(
                        from: file.content,
                        filePath: file.name
                    )

                    return (file: file, issues: issues, stateVars: stateVars)
                }
            }

            var allFiles: [ProjectFile] = []
            var allIssues: [LintIssue] = []
            var allStateVars: [StateVariable] = []
            for await result in group {
                guard let result else { continue }
                allFiles.append(result.file)
                allIssues.append(contentsOf: result.issues)
                allStateVars.append(contentsOf: result.stateVars)
            }
            return (allFiles, allIssues, allStateVars)
        }

        projectFiles = perFileResults.0
        print("DEBUG: Found \(projectFiles.count) project files for analysis")
        var issues = perFileResults.1
        stateVariables = perFileResults.2

        // Sequential cross-file analysis (depends on full file set)
        buildViewHierarchy()
        let crossFileIssues = detectCrossFileIssues(categories: categories)
        issues.append(contentsOf: crossFileIssues)

        // Run cross-file pattern detection using SwiftSyntax, respecting enabled patterns or categories
        let crossFileDetector = self.crossFileDetector ?? CrossFileAnalysisEngine()
        let crossFilePatternIssues: [LintIssue]
        if let ruleIdentifiers = ruleIdentifiers {
            crossFilePatternIssues = crossFileDetector.detectCrossFilePatterns(
                projectFiles: projectFiles,
                ruleIdentifiers: ruleIdentifiers
            )
        } else {
            crossFilePatternIssues = crossFileDetector.detectCrossFilePatterns(
                projectFiles: projectFiles,
                categories: categories
            )
        }
        issues.append(contentsOf: crossFilePatternIssues)

        print("DEBUG: analyzeProject returning \(issues.count) total issues")
        return issues
    }

    /// Extracts state variables from Swift source code using SwiftSyntax parsing.
    ///
    /// This is a pure function (no dependency on instance state) so it can safely be called
    /// from concurrent TaskGroup closures.
    ///
    /// - Parameters:
    ///   - sourceCode: The Swift source code to analyze.
    ///   - filePath: The full file path of the Swift file to analyze.
    /// - Returns: An array of StateVariable instances representing all state variables found in the file.
    private static func extractStateVariables(
        from sourceCode: String,
        filePath: String
    ) -> [StateVariable] {
        let sourceFile = Parser.parse(source: sourceCode)
        let viewName = extractViewName(from: filePath)
        let visitor = StateVariableVisitor(
            viewName: viewName,
            filePath: filePath,
            sourceContents: sourceCode
        )
        visitor.walk(sourceFile)
        return visitor.stateVariables
    }

    /// Extracts the name of a SwiftUI view from a given file path.
    ///
    /// This method assumes that the file name (excluding the `.swift` extension) corresponds to the
    /// name of the SwiftUI view defined in that file. For example, given a file path like
    /// `/Users/example/Project/MyCustomView.swift`, this method will return `"MyCustomView"`.
    ///
    /// - Parameter filePath: The full file system path of the Swift source file.
    /// - Returns: The inferred view name, derived from the file name with the `.swift` extension removed.
    ///
    /// - Note: This approach relies on the convention that each SwiftUI view is declared in a file
    ///         named after the view's struct. If a file contains multiple views or does not follow this
    ///         naming convention, the returned name may not accurately reflect the view's actual type name.
    private static func extractViewName(from filePath: String) -> String {
        let fileName = (filePath as NSString).lastPathComponent
        return fileName.replacingOccurrences(of: ".swift", with: "")
    }

    /// Constructs the view hierarchy for all SwiftUI views detected in the project.
    ///
    /// This method analyzes the collected `stateVariables` to group state properties by their
    /// corresponding views. For each unique view (identified by its name), it creates a `ViewHierarchy`
    /// instance that includes the view's name, its declared state variables, and placeholder values for
    /// `parentView` and `childViews` (which are not currently analyzed in detail). The resulting
    /// hierarchies are stored in the `viewHierarchies` array for later cross-file analysis and
    /// reporting.
    ///
    /// - Note: The current implementation only establishes a flat hierarchy based on state variable grouping and
    ///         does not determine actual parent-child relationships between views. Future enhancements may
    ///         analyze the contents of view bodies to detect nested view compositions and improve
    ///         hierarchy accuracy.
    ///
    /// - SeeAlso: `ViewHierarchy`, `stateVariables`
    private func buildViewHierarchy() {
        // This would analyze view relationships
        // For now, we'll create a simple structure
        let viewNames = Set(stateVariables.map { $0.viewName })

        for viewName in viewNames {
            let viewStateVars = stateVariables.filter {
                $0.viewName == viewName
            }
            let hierarchy = ViewHierarchy(
                viewName: viewName,
                parentView: nil,  // Would be determined by analysis
                childViews: [],  // Would be determined by analysis
                stateVariables: viewStateVars
            )
            viewHierarchies.append(hierarchy)
        }
    }

    /// Detects lint issues that span multiple Swift files, specifically targeting state variable declarations
    /// that appear with the same name across different views (potentially causing source-of-truth or
    /// state propagation problems).
    ///
    /// - Parameters:
    ///   - categories: Optional array of pattern categories to analyze. If nil, analyzes all categories.
    /// - Returns: An array of `LintIssue`
    private func detectCrossFileIssues(
        categories: [PatternCategory]? = nil
    ) -> [LintIssue] {
        let issues: [LintIssue] = []
        // Note: State management cross-file issues are now handled by SwiftSyntax cross-file visitors
        // This method is kept for potential future cross-file analysis that doesn't fit the SwiftSyntax pattern model
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

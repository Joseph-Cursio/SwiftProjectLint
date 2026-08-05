import Foundation
import SwiftParser
//
//  CrossFileAnalysisEngine.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//
import SwiftProjectLintConfig
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// The detector supports cross-file analysis and can detect patterns that span multiple files,
/// such as duplicate state variables across different views.

public class CrossFileAnalysisEngine: CrossFileAnalyzerProtocol {

    private let registry: PatternVisitorRegistry
    private var fileCache: [String: SourceFileSyntax] = [:]

    /// Per-framework allowlist opt-in for the idempotency heuristic
    /// (round-14). Propagated from `LintConfiguration.enabledFrameworkAllowlists`
    /// by `ProjectLinter` and applied to each cross-file visitor before
    /// it walks. `nil` means "all known frameworks active."
    public var enabledFrameworkAllowlists: Set<String>?

    /// Source-relative path prefixes of executable targets, forwarded to each
    /// cross-file visitor before it walks. Set by `ProjectLinter` from
    /// `ExecutableTargetDetector`. Empty means "no app targets known."
    public var executableSourcePaths: [String] = []

    /// Initializes a new SwiftSyntax pattern detector.
    ///
    /// - Parameter registry: The pattern visitor registry to use. Defaults to the shared registry.
    public init(registry: PatternVisitorRegistry = .shared) {
        self.registry = registry
    }

    /// The cached files in a fixed order, so every run walks them the same way.
    ///
    /// `fileCache` is a dictionary, and iterating one yields its elements in an order derived
    /// from the process's hash seed — different on every launch. Any visitor state that depends
    /// on which file came first or last then varies run to run for the same input. Sorting by
    /// path costs one sort per visitor and removes the whole class of drift; a cross-file
    /// visitor that reports "the first of these" now reports the same one every time.
    private var orderedFileCache: [(fileName: String, sourceFile: SourceFileSyntax)] {
        fileCache.sorted { $0.key < $1.key }.map { (fileName: $0.key, sourceFile: $0.value) }
    }

    /// Detects patterns across multiple Swift files with cross-file analysis capabilities.
    ///
    /// This method analyzes multiple files and can detect patterns that span
    /// across files, such as duplicate state variables or architectural issues.
    ///
    /// - Parameters:
    ///   - projectFiles: Array of ProjectFile to analyze.
    ///   - categories: Optional array of pattern categories to analyze.
    /// - Returns: An array of detected lint issues.
    public func detectCrossFilePatterns(
        projectFiles: [ProjectFile],
        categories: [PatternCategory]? = nil,
        preBuiltCache: [String: SourceFileSyntax]? = nil
    ) -> [LintIssue] {
        var allIssues: [LintIssue] = []
        if let preBuiltCache {
            fileCache = preBuiltCache
        } else {
            fileCache = [:]
            for file in projectFiles {
                let sourceFile = Parser.parse(source: file.content)
                fileCache[file.relativePath] = sourceFile
            }
        }

        // Get visitors that support cross-file analysis
        let visitors = getVisitorsForCategories(categories)

        let crossFileVisitors = visitors.filter { visitorType in
            visitorType is CrossFilePatternVisitorProtocol.Type
        }

        for visitorType in crossFileVisitors {
            if let crossFileVisitor = visitorType as? CrossFilePatternVisitorProtocol.Type {
                let visitor = crossFileVisitor.init(fileCache: fileCache)
                configureBaseVisitor(visitor, visitorType: visitorType, categories: categories)

                for (fileName, sourceFile) in orderedFileCache {
                    if let baseVisitor = visitor as? BasePatternVisitor {
                        baseVisitor.setFilePath(fileName)
                        baseVisitor.setSourceLocationConverter(
                            SourceLocationConverter(fileName: fileName, tree: sourceFile)
                        )
                    }
                    visitor.walk(sourceFile)
                }

                // Call finalizeAnalysis for cross-file visitors
                visitor.finalizeAnalysis()

                allIssues.append(contentsOf: visitor.detectedIssues)
            }
        }

        return allIssues
    }

    /// Wires per-analysis-run state into a `BasePatternVisitor`: matches
    /// the visitor's pattern within the requested categories (or the full
    /// registry if none were given) and forwards the framework allowlist.
    /// Non-base visitors are skipped — they don't have these hooks.
    private func configureBaseVisitor(
        _ visitor: CrossFilePatternVisitorProtocol,
        visitorType: PatternVisitorProtocol.Type,
        categories: [PatternCategory]?
    ) {
        guard let baseVisitor = visitor as? BasePatternVisitor else { return }
        let patterns: [SyntaxPattern]
        if let categories {
            patterns = categories.flatMap { registry.getPatterns(for: $0) }
        } else {
            patterns = registry.getAllPatterns()
        }
        if let pattern = patterns.first(where: { $0.visitor == visitorType }) {
            baseVisitor.setPattern(pattern)
        }
        baseVisitor.enabledFrameworkAllowlists = enabledFrameworkAllowlists
        baseVisitor.executableSourcePaths = executableSourcePaths
    }

    /// Detects patterns across multiple Swift files using specific rule identifiers.
    ///
    /// This method analyzes multiple files and can detect patterns that span
    /// across files, such as duplicate state variables or architectural issues.
    /// It only runs the specific patterns requested by rule identifier.
    ///
    /// - Parameters:
    ///   - projectFiles: Array of ProjectFile to analyze.
    ///   - ruleIdentifiers: Array of specific rule identifiers to analyze.
    /// - Returns: An array of detected lint issues.
    public func detectCrossFilePatterns(
        projectFiles: [ProjectFile],
        ruleIdentifiers: [RuleIdentifier],
        preBuiltCache: [String: SourceFileSyntax]? = nil
    ) -> [LintIssue] {
        var allIssues: [LintIssue] = []
        if let preBuiltCache {
            fileCache = preBuiltCache
        } else {
            fileCache = [:]
            for file in projectFiles {
                let sourceFile = Parser.parse(source: file.content)
                fileCache[file.relativePath] = sourceFile
            }
        }

        // Get specific patterns by rule identifier
        let allPatterns = registry.getAllPatterns()
        let requestedPatterns = allPatterns.filter { pattern in
            ruleIdentifiers.contains(pattern.name)
        }

        for pattern in requestedPatterns {
            if let crossFileVisitorType = pattern.visitor as? CrossFilePatternVisitorProtocol.Type {
                let visitor = crossFileVisitorType.init(fileCache: fileCache)
                if let baseVisitor = visitor as? BasePatternVisitor {
                    baseVisitor.setPattern(pattern)
                    baseVisitor.enabledFrameworkAllowlists = enabledFrameworkAllowlists
                    baseVisitor.executableSourcePaths = executableSourcePaths
                }
                for (fileName, sourceFile) in orderedFileCache {
                    if let baseVisitor = visitor as? BasePatternVisitor {
                        baseVisitor.setFilePath(fileName)
                        baseVisitor.setSourceLocationConverter(
                            SourceLocationConverter(fileName: fileName, tree: sourceFile)
                        )
                    }
                    visitor.walk(sourceFile)
                }

                // Call finalizeAnalysis for cross-file visitors
                visitor.finalizeAnalysis()

                allIssues.append(contentsOf: visitor.detectedIssues)
            }
        }

        return allIssues
    }
    /// Detects patterns in the given project path and categories.
    public func detectPatterns(
        in projectPath: String,
        categories: [PatternCategory]? = nil
    ) async -> [LintIssue] {
        let swiftFiles = await FileAnalysisUtils.findSwiftFiles(in: projectPath)
        let projectFiles = await readProjectFiles(from: swiftFiles, projectRoot: projectPath)
        return detectCrossFilePatterns(projectFiles: projectFiles, categories: categories)
    }

    /// Detects patterns in the given project path using specific rule identifiers.
    public func detectPatterns(
        in projectPath: String,
        ruleIdentifiers: [RuleIdentifier]
    ) async -> [LintIssue] {
        let swiftFiles = await FileAnalysisUtils.findSwiftFiles(in: projectPath)
        let projectFiles = await readProjectFiles(from: swiftFiles, projectRoot: projectPath)
        return detectCrossFilePatterns(projectFiles: projectFiles, ruleIdentifiers: ruleIdentifiers)
    }

    /// Reads Swift files in parallel, returning ProjectFile objects with relative paths.
    private func readProjectFiles(from filePaths: [String], projectRoot: String) async -> [ProjectFile] {
        let prefix = projectRoot.hasSuffix("/") ? projectRoot : projectRoot + "/"
        return await withTaskGroup(of: ProjectFile?.self) { group in
            for filePath in filePaths {
                group.addTask {
                    guard let content = try? String(contentsOfFile: filePath) else { return nil }
                    let name = (filePath as NSString).lastPathComponent
                    let relativePath = filePath.hasPrefix(prefix)
                        ? String(filePath.dropFirst(prefix.count))
                        : name
                    return ProjectFile(name: name, content: content, relativePath: relativePath)
                }
            }
            var files: [ProjectFile] = []
            for await file in group {
                if let file { files.append(file) }
            }
            return files
        }
    }

    // MARK: - Private Methods

    private func getVisitorsForCategories(_ categories: [PatternCategory]?) -> [PatternVisitorProtocol.Type] {
        if let categories {
            return categories.flatMap { registry.getVisitors(for: $0) }
        }
        return registry.getAllVisitors()
    }
}

//
//  CrossFileAnalysisEngine.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//
import Foundation
import SwiftParser
import SwiftSyntax

/// The detector supports cross-file analysis and can detect patterns that span multiple files,
/// such as duplicate state variables across different views.

public class CrossFileAnalysisEngine {

    private let registry: PatternVisitorRegistry
    private var fileCache: [String: SourceFileSyntax] = [:]

    /// Initializes a new SwiftSyntax pattern detector.
    ///
    /// - Parameter registry: The pattern visitor registry to use. Defaults to the shared registry.
    public init(registry: PatternVisitorRegistry = .shared) {
        self.registry = registry
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
    func detectCrossFilePatterns(
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

                // Set the pattern for the visitor if it's a BasePatternVisitor
                if let baseVisitor = visitor as? BasePatternVisitor {
                    // Find the pattern that uses this visitor type
                    let patterns: [SyntaxPattern]
                    if let categories = categories {
                        patterns = categories.flatMap { registry.getPatterns(for: $0) }
                    } else {
                        patterns = registry.getAllPatterns()
                    }

                    if let pattern = patterns.first(where: { $0.visitor == visitorType }) {
                        baseVisitor.setPattern(pattern)
                    }
                }

                for (fileName, sourceFile) in fileCache {
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
    func detectCrossFilePatterns(
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
                }
                for (fileName, sourceFile) in fileCache {
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
                    return ProjectFile(name: name, relativePath: relativePath, content: content)
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
        if let categories = categories {
            return categories.flatMap { registry.getVisitors(for: $0) }
        } else {
            return registry.getAllVisitors()
        }
    }

}

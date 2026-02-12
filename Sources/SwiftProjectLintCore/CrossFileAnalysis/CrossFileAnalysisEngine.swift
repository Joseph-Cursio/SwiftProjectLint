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
@MainActor
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
        categories: [PatternCategory]? = nil
    ) -> [LintIssue] {
        print("DEBUG: detectCrossFilePatterns called with \(projectFiles.count) files")
        var allIssues: [LintIssue] = []
        fileCache = [:]
        // Parse all files and cache them
        for file in projectFiles {
            let sourceFile = Parser.parse(source: file.content)
            fileCache[file.name] = sourceFile
        }

        // Get visitors that support cross-file analysis
        let visitors = getVisitorsForCategories(categories)
        print("DEBUG: Total visitors found: \(visitors.count)")
        print("DEBUG: Visitor types: \(visitors.map { String(describing: $0) })")

        let crossFileVisitors = visitors.filter { visitorType in
            // Check if visitor supports cross-file analysis
            let isCrossFile = visitorType is CrossFilePatternVisitorProtocol.Type
            print("DEBUG: Checking visitor \(visitorType): isCrossFile = \(isCrossFile)")
            return isCrossFile
        }

        print("DEBUG: Found \(crossFileVisitors.count) cross-file visitors")

        // Apply cross-file analysis
        for visitorType in crossFileVisitors {
            print("DEBUG: Creating cross-file visitor: \(visitorType)")
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

                for (_, sourceFile) in fileCache {
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
        ruleIdentifiers: [RuleIdentifier]
    ) -> [LintIssue] {
        print("DEBUG: detectCrossFilePatterns (ruleIdentifiers) called " +
              "with \(projectFiles.count) files, rules: \(ruleIdentifiers.map { $0.rawValue })")
        var allIssues: [LintIssue] = []
        fileCache = [:]
        for file in projectFiles {
            let sourceFile = Parser.parse(source: file.content)
            fileCache[file.name] = sourceFile
        }

        // Get specific patterns by rule identifier
        let allPatterns = registry.getAllPatterns()
        let requestedPatterns = allPatterns.filter { pattern in
            ruleIdentifiers.contains(pattern.name)
        }

        print("DEBUG: Found \(requestedPatterns.count) requested patterns")

        // Apply analysis for each visitor type
        for pattern in requestedPatterns {
            print("DEBUG: Processing pattern: \(pattern.name.rawValue) with visitor: \(pattern.visitor)")
            if let crossFileVisitorType = pattern.visitor as? CrossFilePatternVisitorProtocol.Type {
                print("DEBUG: Creating cross-file visitor for pattern: \(pattern.name)")
                let visitor = crossFileVisitorType.init(fileCache: fileCache)
                if let baseVisitor = visitor as? BasePatternVisitor {
                    baseVisitor.setPattern(pattern)
                }
                for (_, sourceFile) in fileCache {
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
    ) -> [LintIssue] {
        let swiftFiles = findSwiftFiles(in: projectPath)
        let projectFiles = swiftFiles.compactMap { filePath -> ProjectFile? in
            guard let content = try? String(contentsOfFile: filePath) else { return nil }
            return ProjectFile(name: (filePath as NSString).lastPathComponent, content: content)
        }
        return detectCrossFilePatterns(projectFiles: projectFiles, categories: categories)
    }

    /// Detects patterns in the given project path using specific rule identifiers.
    public func detectPatterns(
        in projectPath: String,
        ruleIdentifiers: [RuleIdentifier]
    ) -> [LintIssue] {
        let swiftFiles = findSwiftFiles(in: projectPath)
        let projectFiles = swiftFiles.compactMap { filePath -> ProjectFile? in
            guard let content = try? String(contentsOfFile: filePath) else { return nil }
            return ProjectFile(name: (filePath as NSString).lastPathComponent, content: content)
        }
        return detectCrossFilePatterns(projectFiles: projectFiles, ruleIdentifiers: ruleIdentifiers)
    }

    // MARK: - Private Methods

    private func getVisitorsForCategories(_ categories: [PatternCategory]?) -> [PatternVisitorProtocol.Type] {
        if let categories = categories {
            print("DEBUG: Getting visitors for categories: \(categories)")
            let visitors = categories.flatMap { category in
                let categoryVisitors = registry.getVisitors(for: category)
                print(
                    "DEBUG: Category \(category) has \(categoryVisitors.count) visitors: " +
                    "\(categoryVisitors.map { String(describing: $0) })")
                return categoryVisitors
            }
            print("DEBUG: Total visitors from categories: \(visitors.count)")
            return visitors
        } else {
            let allVisitors = registry.getAllVisitors()
            print("DEBUG: All visitors: \(allVisitors.count)")
            return allVisitors
        }
    }

    /// Recursively finds all Swift files in a directory.
    ///
    /// - Parameter path: The directory path to search.
    /// - Returns: An array of Swift file paths.
    private func findSwiftFiles(in path: String) -> [String] {
        let fileManager = FileManager.default
        var swiftFiles: [String] = []

        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return swiftFiles
        }

        while let filePath = enumerator.nextObject() as? String {
            if filePath.hasSuffix(".swift") {
                swiftFiles.append((path as NSString).appendingPathComponent(filePath))
            }
        }

        return swiftFiles
    }
}

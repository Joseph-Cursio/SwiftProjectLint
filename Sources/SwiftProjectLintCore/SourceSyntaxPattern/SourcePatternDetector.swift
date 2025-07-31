import Foundation
import SwiftParser
import SwiftSyntax

@MainActor
public class SourcePatternDetector: SourcePatternDetectorProtocol {
    private let registry: PatternVisitorRegistry
    private var fileCache: [String: SourceFileSyntax] = [:]

    /// Initializes a new SwiftSyntax pattern detector.
    ///
    /// - Parameter registry: The pattern visitor registry to use. Defaults to the shared registry.
    public init(registry: PatternVisitorRegistry = .shared) {
        self.registry = registry
    }

    /// Detects patterns in a single Swift source file using SwiftSyntax analysis.
    ///
    /// - Parameters:
    ///   - sourceCode: The Swift source code to analyze.
    ///   - filePath: The file path for the source code (used for issue reporting).
    ///   - categories: Optional array of pattern categories to analyze. If nil, analyzes all categories.
    /// - Returns: An array of detected lint issues.
    public func detectPatterns(
        in sourceCode: String,
        filePath: String,
        categories: [PatternCategory]? = nil
    ) -> [LintIssue] {
        let sourceFile = Parser.parse(source: sourceCode)
        fileCache[filePath] = sourceFile
        let converter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        var allIssues: [LintIssue] = []
        
        // Get patterns and create visitors with proper initialization
        let patterns = categories != nil ?
        categories!.flatMap { registry.getPatterns(for: $0) } :
        registry.getAllPatterns()

        for pattern in patterns {
            // Create visitor with proper initialization
            if let visitorType = pattern.visitor as? BasePatternVisitor.Type {
                let visitor = visitorType.init(patternCategory: pattern.category)
                visitor.setSourceLocationConverter(converter)
                visitor.setFilePath(filePath)
                visitor.setPattern(pattern)
                visitor.walk(sourceFile)
                allIssues.append(contentsOf: visitor.detectedIssues)
            } else {
                // Fallback for non-BasePatternVisitor types
                let visitor = pattern.visitor.init(viewMode: .sourceAccurate)
                visitor.walk(sourceFile)
                allIssues.append(contentsOf: visitor.detectedIssues)
            }
        }

        return allIssues
    }

    /// Detects specific patterns in the given source code.
    ///
    /// This method parses the source code into an AST and applies only the
    /// specified pattern visitors to detect issues.
    ///
    /// - Parameters:
    ///   - sourceCode: The Swift source code to analyze.
    ///   - filePath: The file path for the source code (used for issue reporting).
    ///   - ruleIdentifiers: Array of specific rule identifiers to analyze.
    /// - Returns: An array of detected lint issues.
    func detectPatterns(
        in sourceCode: String,
        filePath: String,
        ruleIdentifiers: [RuleIdentifier]
    ) -> [LintIssue] {
        let sourceFile = Parser.parse(source: sourceCode)
        fileCache[filePath] = sourceFile
        let converter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        var allIssues: [LintIssue] = []

        // Get specific patterns by rule identifier
        let allPatterns = registry.getAllPatterns()
        let requestedPatterns = allPatterns.filter { pattern in
            ruleIdentifiers.contains(pattern.name)
        }

        for pattern in requestedPatterns {
            // Create visitor with proper initialization
            if let visitorType = pattern.visitor as? BasePatternVisitor.Type {
                let visitor = visitorType.init(patternCategory: pattern.category)
                visitor.setSourceLocationConverter(converter)
                visitor.setFilePath(filePath)
                visitor.setPattern(pattern)
                visitor.walk(sourceFile)
                allIssues.append(contentsOf: visitor.detectedIssues)
            } else {
                // Fallback for non-BasePatternVisitor types
                let visitor = pattern.visitor.init(viewMode: .sourceAccurate)
                visitor.walk(sourceFile)
                allIssues.append(contentsOf: visitor.detectedIssues)
            }
        }

        return allIssues
    }

    /// Clears the internal file cache to free memory.
    public func clearCache() {
        fileCache.removeAll()
    }
    
}

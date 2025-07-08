import Foundation
import SwiftParser
import SwiftSyntax

// MARK: - SwiftSyntax Pattern Detection Infrastructure

/// Protocol defining the interface for SwiftSyntax-based pattern visitors.
/// 
/// `PatternVisitor` provides a standardized way to implement pattern detection
/// using SwiftSyntax AST traversal. Each visitor is responsible for detecting
/// specific patterns within the Swift code and generating appropriate lint issues.
///
/// - Note: All pattern visitors should conform to this protocol and implement
///         the required methods for AST traversal and issue detection.
public protocol PatternVisitor: SyntaxVisitor {
    /// The collection of lint issues detected by this visitor during AST traversal.
    var detectedIssues: [LintIssue] { get }
    
    /// Resets the visitor's internal state, clearing any detected issues.
    /// This method should be called before reusing a visitor instance.
    func reset()
    
    /// The category of patterns this visitor is responsible for detecting.
    var patternCategory: PatternCategory { get }
    
    /// Required initializer for dynamic instantiation.
    init(viewMode: SyntaxTreeViewMode)
}

/// Represents a SwiftSyntax-based pattern definition for code analysis.
///
/// `SyntaxPattern` defines a specific code pattern to detect using SwiftSyntax
/// visitors instead of regex patterns. This provides more accurate and context-aware
/// pattern detection with better semantic understanding of the code structure.
///
/// - Parameters:
///   - name: The display name of the pattern (used for reporting).
///   - visitor: The type of visitor responsible for detecting this pattern.
///   - severity: The level of importance of the detected issue.
///   - category: The logical category of the pattern.
///   - messageTemplate: A template for the issue message, supporting variable interpolation.
///   - suggestion: A recommended action or fix to resolve the detected issue.
///   - description: A detailed description of what this pattern detects.
public struct SyntaxPattern {
    public let name: String
    public let visitor: PatternVisitor.Type
    public let severity: IssueSeverity
    public let category: PatternCategory
    public let messageTemplate: String
    public let suggestion: String
    public let description: String
    
    /// Creates a new syntax pattern with the specified parameters.
    ///
    /// - Parameters:
    ///   - name: The display name of the pattern.
    ///   - visitor: The visitor type responsible for detection.
    ///   - severity: The severity level of detected issues.
    ///   - category: The pattern category.
    ///   - messageTemplate: The message template with variable placeholders.
    ///   - suggestion: The suggested fix or improvement.
    ///   - description: A detailed description of the pattern.
    public init(
        name: String,
        visitor: PatternVisitor.Type,
        severity: IssueSeverity,
        category: PatternCategory,
        messageTemplate: String,
        suggestion: String,
        description: String
    ) {
        self.name = name
        self.visitor = visitor
        self.severity = severity
        self.category = category
        self.messageTemplate = messageTemplate
        self.suggestion = suggestion
        self.description = description
    }
}

/// Registry for managing SwiftSyntax-based pattern visitors and their configurations.
///
/// `PatternVisitorRegistry` provides a centralized way to register, retrieve, and
/// manage pattern visitors for different categories of code analysis. It supports
/// dynamic pattern registration and category-based visitor retrieval.
///
/// - Note: This registry is designed to be thread-safe and supports concurrent access.
public class PatternVisitorRegistry {
    public static let shared = PatternVisitorRegistry()
    
    private var patterns: [SyntaxPattern] = []
    private var visitorsByCategory: [PatternCategory: [PatternVisitor.Type]] = [:]
    private let queue = DispatchQueue(label: "PatternVisitorRegistry", attributes: .concurrent)
    
    public init() {}
    
    /// Registers a new syntax pattern with the registry.
    ///
    /// - Parameter pattern: The syntax pattern to register.
    func register(pattern: SyntaxPattern) {
        queue.sync(flags: .barrier) {
            self.patterns.append(pattern)
            if self.visitorsByCategory[pattern.category] == nil {
                self.visitorsByCategory[pattern.category] = []
            }
            self.visitorsByCategory[pattern.category]?.append(pattern.visitor)
        }
    }
    
    /// Registers multiple syntax patterns at once.
    ///
    /// - Parameter patterns: An array of syntax patterns to register.
    func register(patterns: [SyntaxPattern]) {
        queue.sync(flags: .barrier) {
            for pattern in patterns {
                self.patterns.append(pattern)
                if self.visitorsByCategory[pattern.category] == nil {
                    self.visitorsByCategory[pattern.category] = []
                }
                self.visitorsByCategory[pattern.category]?.append(pattern.visitor)
            }
        }
    }
    
    /// Retrieves all visitor types for a specific pattern category.
    ///
    /// - Parameter category: The pattern category to retrieve visitors for.
    /// - Returns: An array of visitor types for the specified category.
    func getVisitors(for category: PatternCategory) -> [PatternVisitor.Type] {
        return queue.sync {
            let visitors = visitorsByCategory[category] ?? []
            print("DEBUG: Registry.getVisitors(for: \(category)) returning \(visitors.count) visitors")
            print("DEBUG: Available categories in registry: \(visitorsByCategory.keys.map { $0 })")
            return visitors
        }
    }
    
    /// Retrieves all registered visitor types.
    ///
    /// - Returns: An array of all registered visitor types.
    func getAllVisitors() -> [PatternVisitor.Type] {
        return queue.sync {
            return patterns.map { $0.visitor }
        }
    }
    
    /// Retrieves all registered syntax patterns.
    ///
    /// - Returns: An array of all registered syntax patterns.
    func getAllPatterns() -> [SyntaxPattern] {
        return queue.sync {
            return patterns
        }
    }
    
    /// Retrieves syntax patterns for a specific category.
    ///
    /// - Parameter category: The pattern category to retrieve patterns for.
    /// - Returns: An array of syntax patterns for the specified category.
    func getPatterns(for category: PatternCategory) -> [SyntaxPattern] {
        return queue.sync {
            return patterns.filter { $0.category == category }
        }
    }
    
    /// Clears all registered patterns and visitors.
    func clear() {
        queue.sync(flags: .barrier) {
            self.patterns.removeAll()
            self.visitorsByCategory.removeAll()
        }
    }
}

// MARK: - SwiftSyntax Pattern Detector

/// The detector supports cross-file analysis and can detect patterns that span multiple files,
/// such as duplicate state variables across different views.
public class SwiftSyntaxPatternDetector {
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
    /// This method parses the source code into an AST and applies all registered
    /// pattern visitors to detect issues. The analysis is more accurate than
    /// regex-based detection and provides better context awareness.
    ///
    /// - Parameters:
    ///   - sourceCode: The Swift source code to analyze.
    ///   - filePath: The file path for the source code (used for issue reporting).
    ///   - categories: Optional array of pattern categories to analyze. If nil, analyzes all categories.
    /// - Returns: An array of detected lint issues.
    func detectPatterns(
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
    ///   - patternNames: Array of specific pattern names to analyze.
    /// - Returns: An array of detected lint issues.
    func detectPatterns(
        in sourceCode: String,
        filePath: String,
        patternNames: [String]
    ) -> [LintIssue] {
        let sourceFile = Parser.parse(source: sourceCode)
        fileCache[filePath] = sourceFile
        let converter = SourceLocationConverter(fileName: filePath, tree: sourceFile)
        var allIssues: [LintIssue] = []
        
        // Get specific patterns by name
        let allPatterns = registry.getAllPatterns()
        let requestedPatterns = allPatterns.filter { pattern in
            patternNames.contains(pattern.name)
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
    
    /// Detects patterns in the given project path and categories.
    public func detectPatterns(
        in projectPath: String,
        categories: [PatternCategory]? = nil
    ) -> [LintIssue] {
        let swiftFiles = findSwiftFiles(in: projectPath)
        return detectCrossFilePatterns(projectFiles: swiftFiles, categories: categories)
    }
    
    /// Detects patterns in the given project path using specific pattern names.
    public func detectPatterns(
        in projectPath: String,
        patternNames: [String]
    ) -> [LintIssue] {
        let swiftFiles = findSwiftFiles(in: projectPath)
        return detectCrossFilePatterns(projectFiles: swiftFiles, patternNames: patternNames)
    }
    
    /// Detects patterns across multiple Swift files with cross-file analysis capabilities.
    ///
    /// This method analyzes multiple files and can detect patterns that span
    /// across files, such as duplicate state variables or architectural issues.
    ///
    /// - Parameters:
    ///   - projectFiles: Array of file paths to analyze.
    ///   - categories: Optional array of pattern categories to analyze.
    /// - Returns: An array of detected lint issues.
    func detectCrossFilePatterns(
        projectFiles: [String],
        categories: [PatternCategory]? = nil
    ) -> [LintIssue] {
        print("DEBUG: detectCrossFilePatterns called with \(projectFiles.count) files")
        var allIssues: [LintIssue] = []
        
        // First, parse all files and cache them
        for filePath in projectFiles {
            do {
                let sourceCode = try String(contentsOfFile: filePath)
                let sourceFile = Parser.parse(source: sourceCode)
                fileCache[filePath] = sourceFile
            } catch {
                allIssues.append(
                    LintIssue(
                        severity: .error,
                        message: "Failed to read or parse file: \(error.localizedDescription)",
                        filePath: filePath,
                        lineNumber: 1,
                        suggestion: "Check file permissions and syntax",
                        ruleName: "File Parsing Error"
                    )
                )
            }
        }
        
        // Get visitors that support cross-file analysis
        let visitors = getVisitorsForCategories(categories)
        print("DEBUG: Total visitors found: \(visitors.count)")
        print("DEBUG: Visitor types: \(visitors.map { String(describing: $0) })")
        
        let crossFileVisitors = visitors.filter { visitorType in
            // Check if visitor supports cross-file analysis
            let isCrossFile = visitorType is CrossFilePatternVisitor.Type
            print("DEBUG: Checking visitor \(visitorType): isCrossFile = \(isCrossFile)")
            return isCrossFile
        }
        
        print("DEBUG: Found \(crossFileVisitors.count) cross-file visitors")
        
        // Apply cross-file analysis
        for visitorType in crossFileVisitors {
            print("DEBUG: Creating cross-file visitor: \(visitorType)")
            if let crossFileVisitor = visitorType as? CrossFilePatternVisitor.Type {
                let visitor = crossFileVisitor.init(fileCache: fileCache)
                
                // Set the pattern for the visitor if it's a BasePatternVisitor
                if let baseVisitor = visitor as? BasePatternVisitor {
                    // Find the pattern that uses this visitor type
                    let patterns = categories != nil ? 
                        categories!.flatMap { registry.getPatterns(for: $0) } : 
                        registry.getAllPatterns()
                    
                    if let pattern = patterns.first(where: { $0.visitor == visitorType }) {
                        baseVisitor.setPattern(pattern)
                    }
                }
                
                for (_, sourceFile) in fileCache {
                    visitor.walk(sourceFile)
                }
                
                // Call finalizeAnalysis for cross-file visitors
                if let crossFileVisitor = visitor as? CrossFilePatternVisitor {
                    crossFileVisitor.finalizeAnalysis()
                }
                
                allIssues.append(contentsOf: visitor.detectedIssues)
            }
        }
        
        return allIssues
    }
    
    /// Detects patterns across multiple Swift files using specific pattern names.
    ///
    /// This method analyzes multiple files and can detect patterns that span
    /// across files, such as duplicate state variables or architectural issues.
    /// It only runs the specific patterns requested by name.
    ///
    /// - Parameters:
    ///   - projectFiles: Array of file paths to analyze.
    ///   - patternNames: Array of specific pattern names to analyze.
    /// - Returns: An array of detected lint issues.
    func detectCrossFilePatterns(
        projectFiles: [String],
        patternNames: [String]
    ) -> [LintIssue] {
        print("DEBUG: detectCrossFilePatterns (patternNames) called with \(projectFiles.count) files, patterns: \(patternNames)")
        var allIssues: [LintIssue] = []
        
        // First, parse all files and cache them
        for filePath in projectFiles {
            do {
                let sourceCode = try String(contentsOfFile: filePath)
                let sourceFile = Parser.parse(source: sourceCode)
                fileCache[filePath] = sourceFile
            } catch {
                allIssues.append(
                    LintIssue(
                        severity: .error,
                        message: "Failed to read or parse file: \(error.localizedDescription)",
                        filePath: filePath,
                        lineNumber: 1,
                        suggestion: "Check file permissions and syntax",
                        ruleName: "File Parsing Error"
                    )
                )
            }
        }
        
        // Get specific patterns by name
        let allPatterns = registry.getAllPatterns()
        let requestedPatterns = allPatterns.filter { pattern in
            patternNames.contains(pattern.name)
        }
        
        print("DEBUG: Found \(requestedPatterns.count) requested patterns")
        
        // Group patterns by their name (String) instead of visitor type
        let patternsByName = Dictionary(grouping: requestedPatterns) { $0.name }
        
        // Apply analysis for each visitor type
        for pattern in requestedPatterns {
            print("DEBUG: Processing pattern: \(pattern.name) with visitor: \(pattern.visitor)")
            if let crossFileVisitorType = pattern.visitor as? CrossFilePatternVisitor.Type {
                print("DEBUG: Creating cross-file visitor for pattern: \(pattern.name)")
                let visitor = crossFileVisitorType.init(fileCache: fileCache)
                if let baseVisitor = visitor as? BasePatternVisitor {
                    baseVisitor.setPattern(pattern)
                }
                for (_, sourceFile) in fileCache {
                    visitor.walk(sourceFile)
                }
                
                // Call finalizeAnalysis for cross-file visitors
                if let crossFileVisitor = visitor as? CrossFilePatternVisitor {
                    crossFileVisitor.finalizeAnalysis()
                }
                
                allIssues.append(contentsOf: visitor.detectedIssues)
            }
        }
        
        return allIssues
    }
    
    /// Clears the internal file cache to free memory.
    func clearCache() {
        fileCache.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func getVisitorsForCategories(_ categories: [PatternCategory]?) -> [PatternVisitor.Type] {
        if let categories = categories {
            print("DEBUG: Getting visitors for categories: \(categories)")
            let visitors = categories.flatMap { category in
                let categoryVisitors = registry.getVisitors(for: category)
                print("DEBUG: Category \(category) has \(categoryVisitors.count) visitors: \(categoryVisitors.map { String(describing: $0) })")
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

// MARK: - Cross-File Pattern Visitor Protocol

/// Protocol for pattern visitors that support cross-file analysis.
///
/// `CrossFilePatternVisitor` extends `PatternVisitor` to support analysis
/// that spans multiple files, such as duplicate detection or architectural
/// pattern analysis.
protocol CrossFilePatternVisitor: PatternVisitor {
    /// The cached source files for cross-file analysis.
    var fileCache: [String: SourceFileSyntax] { get }
    
    /// Creates a new cross-file pattern visitor with access to the file cache.
    ///
    /// - Parameter fileCache: A dictionary mapping file paths to their parsed ASTs.
    init(fileCache: [String: SourceFileSyntax])
    
    /// Performs final analysis after all files have been processed.
    func finalizeAnalysis()
}

// MARK: - Base Pattern Visitor Implementation

/// Base implementation of `PatternVisitor` providing common functionality.
///
/// `BasePatternVisitor` provides a foundation for implementing specific pattern
/// visitors with common utilities and helper methods for AST analysis.
class BasePatternVisitor: SyntaxVisitor, PatternVisitor {
    var detectedIssues: [LintIssue] = []
    let patternCategory: PatternCategory
    var sourceLocationConverter: SourceLocationConverter?
    
    // Pattern information for message template support
    var currentPattern: SyntaxPattern?
    
    required init(patternCategory: PatternCategory) {
        self.patternCategory = patternCategory
        super.init(viewMode: .sourceAccurate)
    }
    
    func reset() {
        detectedIssues.removeAll()
    }
    
    /// Sets the current pattern for message template support.
    ///
    /// - Parameter pattern: The pattern to use for message templates.
    func setPattern(_ pattern: SyntaxPattern) {
        self.currentPattern = pattern
    }
    
    /// Adds a detected issue to the visitor's issue collection.
    ///
    /// - Parameters:
    ///   - severity: The severity level of the issue.
    ///   - message: The issue message.
    ///   - filePath: The file path where the issue was detected.
    ///   - lineNumber: The line number where the issue was detected.
    ///   - suggestion: Optional suggestion for fixing the issue.
    ///   - ruleName: The name of the rule that generated this issue.
    func addIssue(
        severity: IssueSeverity,
        message: String,
        filePath: String,
        lineNumber: Int,
        suggestion: String? = nil,
        ruleName: String? = nil
    ) {
        let issue = LintIssue(
            severity: severity,
            message: message,
            filePath: filePath,
            lineNumber: lineNumber,
            suggestion: suggestion,
            ruleName: ruleName ?? currentPattern?.name ?? "Unknown Rule"
        )
        detectedIssues.append(issue)
    }
    
    /// Adds a detected issue using the pattern's message template.
    ///
    /// - Parameters:
    ///   - filePath: The file path where the issue was detected.
    ///   - lineNumber: The line number where the issue was detected.
    ///   - variables: Variables to substitute in the message template.
    func addIssueWithTemplate(
        filePath: String,
        lineNumber: Int,
        variables: [String: String] = [:]
    ) {
        guard let pattern = currentPattern else {
            // Fallback to default behavior if no pattern is set
            addIssue(
                severity: .warning,
                message: "Pattern issue detected",
                filePath: filePath,
                lineNumber: lineNumber,
                suggestion: "Review the code",
                ruleName: "Unknown Rule"
            )
            return
        }
        
        let message = substituteVariables(in: pattern.messageTemplate, with: variables)
        let suggestion = substituteVariables(in: pattern.suggestion, with: variables)
        
        let issue = LintIssue(
            severity: pattern.severity,
            message: message,
            filePath: filePath,
            lineNumber: lineNumber,
            suggestion: suggestion,
            ruleName: pattern.name
        )
        detectedIssues.append(issue)
    }
    
    /// Substitutes variables in a template string.
    ///
    /// - Parameters:
    ///   - template: The template string containing variable placeholders.
    ///   - variables: The variables to substitute.
    /// - Returns: The template string with variables substituted.
    private func substituteVariables(in template: String, with variables: [String: String]) -> String {
        var result = template
        
        for (key, value) in variables {
            let placeholder = "{\(key)}"
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        
        return result
    }
    
    /// Gets the line number for a syntax node.
    ///
    /// - Parameter node: The syntax node to get the line number for.
    /// - Returns: The line number where the node appears.
    func getLineNumber(for node: Syntax) -> Int {
        guard let converter = sourceLocationConverter else { return 1 }
        let position = node.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        return location.line ?? 1
    }
    
    /// Gets the file path for a syntax node.
    ///
    /// - Parameter node: The syntax node to get the file path for.
    /// - Returns: The file path where the node appears.
    func getFilePath(for node: Syntax) -> String {
        // This would need to be implemented based on how we track file paths
        // For now, we'll need to pass this information through the visitor
        return "unknown"
    }
    
    required override init(viewMode: SyntaxTreeViewMode) {
        self.patternCategory = .stateManagement // Default, subclasses should override if needed
        super.init(viewMode: viewMode)
    }
    
    func setSourceLocationConverter(_ converter: SourceLocationConverter) {
        self.sourceLocationConverter = converter
    }
    
    /// Sets the current file path for issue reporting.
    ///
    /// - Parameter filePath: The file path to set.
    func setFilePath(_ filePath: String) {
        // This is a base implementation - subclasses can override if needed
    }
} 
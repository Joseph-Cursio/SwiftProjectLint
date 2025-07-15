//
//  BasePatternVisitor.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/9/25.
//
import SwiftSyntax

/// Base implementation of `PatternVisitorProtocol` providing common functionality.
///
/// `BasePatternVisitor` provides a foundation for implementing specific pattern
/// visitors with common utilities and helper methods for AST analysis.
class BasePatternVisitor: SyntaxVisitor, PatternVisitorProtocol {
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
        ruleName: RuleIdentifier? = nil
    ) {
        let issue = LintIssue(
            severity: severity,
            message: message,
            filePath: filePath,
            lineNumber: lineNumber,
            suggestion: suggestion,
            ruleName: .fileParsingError
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
                ruleName: .fileParsingError
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

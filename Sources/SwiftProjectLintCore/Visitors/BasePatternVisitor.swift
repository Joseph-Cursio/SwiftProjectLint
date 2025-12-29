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
    let pattern: SyntaxPattern
    var sourceLocationConverter: SourceLocationConverter?

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.pattern = pattern
        super.init(viewMode: viewMode)
    }

    func reset() {
        detectedIssues.removeAll()
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
        node: Syntax,
        variables: [String: String] = [:]
    ) {
        let message = substituteVariables(in: pattern.messageTemplate, with: variables)
        let suggestion = substituteVariables(in: pattern.suggestion, with: variables)

        let issue = LintIssue(
            severity: pattern.severity,
            message: message,
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
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
        return location.line
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

//
//  BasePatternVisitor.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/9/25.
//
import SwiftProjectLintModels
import SwiftSyntax

/// Base implementation of `PatternVisitorProtocol` providing common functionality.
///
/// `BasePatternVisitor` provides a foundation for implementing specific pattern
/// visitors with common utilities and helper methods for AST analysis.
open class BasePatternVisitor: SyntaxVisitor, PatternVisitorProtocol {
    public var detectedIssues: [LintIssue] = []
    public var pattern: SyntaxPattern
    public var sourceLocationConverter: SourceLocationConverter?
    private var filePath: String = "unknown"

    /// Type names known to conform to `Identifiable` across the project.
    /// Populated by a pre-scan phase in `ProjectLinter` so that per-file
    /// visitors can suppress false positives (e.g. ForEach without explicit `id:`
    /// when the element type is `Identifiable`).
    public var knownIdentifiableTypes: Set<String> = []

    /// Type names known to be declared as enums across the project.
    /// Populated by a pre-scan phase in `ProjectLinter` so that per-file
    /// visitors can exempt enum-typed parameters and properties from rules
    /// that only apply to class/struct service types (e.g. Concrete Type Usage).
    public var knownEnumTypes: Set<String> = []

    /// Type names known to be declared as actors across the project.
    /// Populated by a pre-scan phase in `ProjectLinter` so that per-file
    /// visitors can exempt actor-typed parameters and properties from rules like
    /// "Concrete Type Usage". An actor's isolation contract is load-bearing in
    /// Swift 6 strict concurrency — protocol-abstracting it weakens that contract.
    public var knownActorTypes: Set<String> = []

    /// Placeholder pattern used for cross-file visitors that set their pattern after initialization.
    public static let placeholderPattern = SyntaxPattern(
        name: .unknown,
        visitor: BasePatternVisitor.self,
        severity: .warning,
        category: .other,
        messageTemplate: "",
        suggestion: "",
        description: ""
    )

    public required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.pattern = pattern
        super.init(viewMode: viewMode)
    }

    /// Convenience initializer for tests and simple usage.
    /// Creates a visitor with a placeholder pattern for the given category.
    public convenience init(patternCategory: PatternCategory, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        let placeholder = SyntaxPattern(
            name: .unknown,
            visitor: BasePatternVisitor.self,
            severity: .warning,
            category: patternCategory,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        self.init(pattern: placeholder, viewMode: viewMode)
    }

    /// Sets the pattern for this visitor. Used by cross-file analysis engines.
    public func setPattern(_ pattern: SyntaxPattern) {
        self.pattern = pattern
    }

    open func reset() {
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
    public func addIssue(
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
    open func getLineNumber(for node: Syntax) -> Int {
        guard let converter = sourceLocationConverter else { return 1 }
        let position = node.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        return location.line
    }

    /// Gets the file path for a syntax node.
    ///
    /// - Parameter node: The syntax node to get the file path for.
    /// - Returns: The file path where the node appears.
    public func getFilePath(for node: Syntax) -> String {
        return filePath
    }

    open func setSourceLocationConverter(_ converter: SourceLocationConverter) {
        self.sourceLocationConverter = converter
    }

    /// Sets the current file path for issue reporting.
    ///
    /// - Parameter filePath: The file path to set.
    open func setFilePath(_ filePath: String) {
        self.filePath = filePath
    }

    /// Adds a detected issue directly with explicit parameters.
    ///
    /// Use this method when you need to create issues with custom messages
    /// that don't come from the pattern template.
    ///
    /// - Parameters:
    ///   - severity: The severity level of the issue.
    ///   - message: The issue message.
    ///   - filePath: The file path where the issue was detected.
    ///   - lineNumber: The line number where the issue was detected.
    ///   - suggestion: Optional suggestion for fixing the issue.
    ///   - ruleName: The name of the rule that generated this issue.
    public func addIssue(
        severity: IssueSeverity,
        message: String,
        filePath: String,
        lineNumber: Int,
        suggestion: String,
        ruleName: RuleIdentifier?
    ) {
        let issue = LintIssue(
            severity: severity,
            message: message,
            filePath: filePath,
            lineNumber: lineNumber,
            suggestion: suggestion,
            ruleName: ruleName ?? pattern.name
        )
        detectedIssues.append(issue)
    }
}

//
//  SyntaxPattern.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//

public struct SyntaxPattern {
    public let name: RuleIdentifier
    public let visitor: PatternVisitor.Type
    public let severity: IssueSeverity
    public let category: PatternCategory
    public let messageTemplate: String
    public let suggestion: String
    public let description: String
    
    /// Creates a new syntax pattern with the specified parameters.
    ///
    /// - Parameters:
    ///   - name: The rule identifier of the pattern.
    ///   - visitor: The visitor type responsible for detection.
    ///   - severity: The severity level of detected issues.
    ///   - category: The pattern category.
    ///   - messageTemplate: The message template with variable placeholders.
    ///   - suggestion: The suggested fix or improvement.
    ///   - description: A detailed description of the pattern.
    public init(
        name: RuleIdentifier,
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

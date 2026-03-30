import Foundation
import SwiftProjectLintModels

// MARK: - Detection Pattern (UI Compatibility)

/// Represents a code pattern to detect within Swift source files, used for UI compatibility.
/// This struct provides a bridge between the SwiftSyntax-based pattern system and the UI layer.
/// Each detection pattern is associated with a category, severity level, user-facing message, and suggestion.
///
/// Detection patterns are used by the UI to display available patterns and their configuration.
///
/// - Parameters:
///   - name: The rule identifier for the pattern (used for type-safe rule identification).
///   - severity: The level of importance of the detected issue (e.g., info, warning, error).
///   - message: A user-facing message template.
///   - suggestion: A recommended action or fix to resolve the detected issue.
///   - category: The logical category of the pattern (such as code quality, performance, or security).
public struct DetectionPattern {
    public let name: RuleIdentifier
    public let severity: IssueSeverity
    public let message: String
    public let suggestion: String
    public let category: PatternCategory
    
    public init(name: RuleIdentifier, severity: IssueSeverity, message: String, suggestion: String, category: PatternCategory) {
        self.name = name
        self.severity = severity
        self.message = message
        self.suggestion = suggestion
        self.category = category
    }
} 

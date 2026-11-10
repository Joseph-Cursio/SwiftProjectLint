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
    /// The rule this pattern detects.
    public let name: RuleIdentifier
    /// How serious a finding of this pattern is.
    public let severity: IssueSeverity
    /// The user-facing message template shown for a finding.
    public let message: String
    /// The fix the UI recommends for a finding.
    public let suggestion: String
    /// The category the UI groups this pattern under.
    public let category: PatternCategory

    /// A pattern with the given rule, severity, message, suggestion and category.
    public init(
        name: RuleIdentifier,
        severity: IssueSeverity,
        message: String,
        suggestion: String,
        category: PatternCategory
    ) {
        self.name = name
        self.severity = severity
        self.message = message
        self.suggestion = suggestion
        self.category = category
    }
}

//
//  supports.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//


/// Represents a lint issue detected during static analysis of the project.
///
/// `LintIssue` describes a specific problem, warning, or suggestion found in the codebase. It includes the severity of the issue,
/// a descriptive message, and one or more locations where the issue occurs, as well as an optional suggestion for remediation.
///
/// - Parameters:
///   - severity: The severity of the issue (e.g., `.error`, `.warning`, `.info`). See `IssueSeverity`.
///   - message: A human-readable description of the detected issue.
///   - locations: One or more locations (file path and line number) where the issue was detected.
///   - suggestion: An optional fix or recommendation to resolve the issue, or `nil` if no suggestion is provided.
///   - ruleName: The identifier of the rule that generated this issue.
///
/// - Note: This struct supports multiple locations for a single issue. For backward compatibility, single-location
///         initializers and computed properties are provided.
///
/// - SeeAlso: `IssueSeverity`
public struct LintIssue: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let severity: IssueSeverity
    public let message: String
    /// The locations (file path and line number pairs) where the issue occurs.
    /// This supports issues that span multiple files or lines.
    public let locations: [(filePath: String, lineNumber: Int)]
    public let suggestion: String?
    public let ruleName: RuleIdentifier
    
    /// Returns the file path of the first location, or an empty string if no locations exist.
    public var filePath: String {
        return locations.first?.filePath ?? ""
    }
    
    /// Returns the line number of the first location, or 0 if no locations exist.
    public var lineNumber: Int {
        return locations.first?.lineNumber ?? 0
    }
    
    /// Initializes a lint issue with multiple locations.
    ///
    /// - Parameters:
    ///   - severity: The severity of the issue.
    ///   - message: The message describing the issue.
    ///   - locations: An array of file path and line number tuples where the issue occurs.
    ///   - suggestion: An optional suggestion for fixing the issue.
    ///   - ruleName: The identifier of the rule that generated this issue.
    public init(severity: IssueSeverity, message: String, locations: [(filePath: String, lineNumber: Int)], suggestion: String?, ruleName: RuleIdentifier) {
        self.severity = severity
        self.message = message
        self.locations = locations
        self.suggestion = suggestion
        self.ruleName = ruleName
    }
    
    /// Initializes a lint issue with a single location.
    /// For backward compatibility, this initializer populates the `locations` array with one element.
    ///
    /// - Parameters:
    ///   - severity: The severity of the issue.
    ///   - message: The message describing the issue.
    ///   - filePath: The file path where the issue occurs.
    ///   - lineNumber: The line number where the issue occurs.
    ///   - suggestion: An optional suggestion for fixing the issue.
    ///   - ruleName: The identifier of the rule that generated this issue.
    public init(severity: IssueSeverity, message: String, filePath: String, lineNumber: Int, suggestion: String?, ruleName: RuleIdentifier) {
        self.severity = severity
        self.message = message
        self.locations = [(filePath, lineNumber)]
        self.suggestion = suggestion
        self.ruleName = ruleName
    }
}
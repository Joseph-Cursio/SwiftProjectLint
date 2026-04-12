import Foundation
import SwiftProjectLintModels

/// A Codable-friendly location for lint issues.
public struct IssueLocation: Codable, Sendable {
    public let filePath: String
    public let lineNumber: Int
}

/// A Codable wrapper around LintIssue for JSON serialization.
///
/// LintIssue uses tuple-based locations which aren't directly Codable,
/// so this struct provides a clean mapping without modifying Core types.
public struct CodableLintIssue: Codable, Sendable {
    public let severity: String
    public let message: String
    public let locations: [IssueLocation]
    public let suggestion: String?
    public let ruleName: String
    public let category: String

    public init(from issue: LintIssue) {
        self.severity = issue.severity.rawValue
        self.message = issue.message
        self.locations = issue.locations.map {
            IssueLocation(filePath: $0.filePath, lineNumber: $0.lineNumber)
        }
        self.suggestion = issue.suggestion
        self.ruleName = issue.ruleName.rawValue
        self.category = String(describing: issue.ruleName.category)
    }
}

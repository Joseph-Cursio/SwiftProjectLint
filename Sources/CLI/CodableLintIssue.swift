import Foundation
import Core

/// A Codable-friendly location for lint issues.
// swiftprojectlint:disable:this could-be-private
struct IssueLocation: Codable {
    let filePath: String
    let lineNumber: Int
}

/// A Codable wrapper around LintIssue for JSON serialization.
///
/// LintIssue uses tuple-based locations which aren't directly Codable,
/// so this struct provides a clean mapping without modifying Core types.
struct CodableLintIssue: Codable {
    let severity: String
    let message: String
    let locations: [IssueLocation]
    let suggestion: String?
    let ruleName: String
    let category: String

    init(from issue: LintIssue) {
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


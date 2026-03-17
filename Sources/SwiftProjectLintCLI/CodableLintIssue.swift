import Foundation
import SwiftProjectLintCore

/// A Codable-friendly location for lint issues.
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

/// Top-level JSON report structure.
struct LintReport: Codable {
    let summary: ReportSummary
    let issues: [CodableLintIssue]
}

/// Summary counts for the JSON report.
struct ReportSummary: Codable {
    let totalIssues: Int
    let errorCount: Int
    let warningCount: Int
    let infoCount: Int
}

import SwiftProjectLintModels

/// Contract for types that render lint issues into a string report.
public protocol IssueFormatterProtocol {
    func format(issues: [LintIssue]) -> String
}

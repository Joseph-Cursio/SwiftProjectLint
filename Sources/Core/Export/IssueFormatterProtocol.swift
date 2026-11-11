import SwiftProjectLintModels

/// Contract for types that render lint issues into a string report.
public protocol IssueFormatterProtocol {
    /// The report for `issues`, in this formatter's format.
    func format(issues: [LintIssue]) -> String
}

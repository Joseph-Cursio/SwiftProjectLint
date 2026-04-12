import Foundation

/// Top-level JSON report structure.
public struct LintReport: Codable, Sendable {
    public let summary: ReportSummary
    public let issues: [CodableLintIssue]

    public init(summary: ReportSummary, issues: [CodableLintIssue]) {
        self.summary = summary
        self.issues = issues
    }
}

import Foundation

/// Top-level JSON report structure.
struct LintReport: Codable {
    let summary: ReportSummary
    let issues: [CodableLintIssue]
}

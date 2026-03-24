import Foundation

/// Summary counts for the JSON report.
struct ReportSummary: Codable {
    let totalIssues: Int
    let errorCount: Int
    let warningCount: Int
    let infoCount: Int
}

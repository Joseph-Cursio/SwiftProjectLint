import Foundation

/// Summary counts for the JSON report.
public struct ReportSummary: Codable, Sendable {
    public let totalIssues: Int
    public let errorCount: Int
    public let warningCount: Int
    public let infoCount: Int

    public init(totalIssues: Int, errorCount: Int, warningCount: Int, infoCount: Int) {
        self.totalIssues = totalIssues
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.infoCount = infoCount
    }
}

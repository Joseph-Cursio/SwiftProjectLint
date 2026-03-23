import Foundation
import Core

/// Formats lint issues as a JSON report.
struct JSONFormatter {
    /// Formats a list of lint issues as a pretty-printed JSON string.
    static func format(issues: [LintIssue]) -> String {
        let codableIssues = issues.map { CodableLintIssue(from: $0) }

        let summary = ReportSummary(
            totalIssues: issues.count,
            errorCount: issues.filter { $0.severity == .error }.count,
            warningCount: issues.filter { $0.severity == .warning }.count,
            infoCount: issues.filter { $0.severity == .info }.count
        )

        let report = LintReport(summary: summary, issues: codableIssues)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(report),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{\"error\": \"Failed to encode report\"}"
        }

        return jsonString
    }
}

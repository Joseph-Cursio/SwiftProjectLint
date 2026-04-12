import SwiftProjectLintModels

/// Formats lint issues as human-readable text in the style of compiler diagnostics.
public struct TextFormatter: IssueFormatterProtocol {
    public init() {}

    /// Formats a list of lint issues as text lines.
    ///
    /// Each issue is formatted as:
    ///   `filepath:line: severity: [ruleName] message`
    /// with an optional indented suggestion line below.
    public func format(issues: [LintIssue]) -> String {
        var lines: [String] = []

        for issue in issues {
            let severity = issue.severity.rawValue
            let rule = issue.ruleName.rawValue
            let filePath = issue.filePath
            let lineNumber = issue.lineNumber

            lines.append("\(filePath):\(lineNumber): \(severity): [\(rule)] \(issue.message)")

            if let suggestion = issue.suggestion {
                lines.append("  suggestion: \(suggestion)")
            }
        }

        lines.append("")
        lines.append(summaryLine(for: issues))

        return lines.joined(separator: "\n")
    }

    /// Returns a summary line like "Found 5 issues (1 error, 3 warnings, 1 info)".
    public func summaryLine(for issues: [LintIssue]) -> String {
        let errorCount = issues.filter { $0.severity == .error }.count
        let warningCount = issues.filter { $0.severity == .warning }.count
        let infoCount = issues.filter { $0.severity == .info }.count

        var parts: [String] = []
        if errorCount > 0 {
            parts.append("\(errorCount) \(errorCount == 1 ? "error" : "errors")")
        }
        if warningCount > 0 {
            parts.append("\(warningCount) \(warningCount == 1 ? "warning" : "warnings")")
        }
        if infoCount > 0 {
            parts.append("\(infoCount) info")
        }

        let total = issues.count
        if total == 0 {
            return "No issues found."
        }

        let detail = parts.joined(separator: ", ")
        return "Found \(total) \(total == 1 ? "issue" : "issues") (\(detail))"
    }
}

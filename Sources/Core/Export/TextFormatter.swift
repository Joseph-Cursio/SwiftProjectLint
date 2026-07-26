import SwiftProjectLintModels

/// Formats lint issues as human-readable text in the style of compiler diagnostics.
public struct TextFormatter: IssueFormatterProtocol {

    /// Candidates counted but not listed — see `CandidateInventory`.
    ///
    /// Held here rather than filtered by the caller so the **summary stays honest**. If the CLI
    /// simply passed fewer issues, "Found 212 issues" would be a silent undercount of a run that
    /// found 876, which is the same species of lie as the confident zero this project keeps
    /// designing against. The count covers everything; only the enumeration is shortened.
    private let withheld: [LintIssue]

    public init(withheld: [LintIssue] = []) {
        self.withheld = withheld
    }

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
        lines.append(summaryLine(for: issues + withheld))
        lines.append(contentsOf: inventoryNotice())

        return lines.joined(separator: "\n")
    }

    /// Names what was counted but not printed, and how to reach it.
    ///
    /// Two routes, because they serve different readers: a person who wants to look gets a flag,
    /// and the pipeline gets the manifest. Withholding without saying where to look would be
    /// hiding, which is worse than the wall of text it replaces.
    private func inventoryNotice() -> [String] {
        guard !withheld.isEmpty else { return [] }
        let breakdown = CandidateInventory.tally(of: withheld)
            .map { "\($0.count) \($0.rule.rawValue)" }
            .joined(separator: ", ")
        return [
            "",
            "\(withheld.count) of these are property-test candidates, not listed above "
                + "(\(breakdown)).",
            "  They are an inventory of what COULD be property-tested — a pure function is not a "
                + "defect, and there is nothing to fix per line.",
            "  See them:  --categories testability",
            "  Use them:  --format pbt-seeds > .pbt/seeds.json   "
                + "(then `swift-infer discover --seeds .pbt/seeds.json`)"
        ]
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

import Foundation
import Core
import LintStudioCore

/// Formats lint issues as a CSV report using the shared LintStudioCore escaping.
struct CSVFormatter: IssueFormatterProtocol {
    func format(issues: [LintIssue]) -> String {
        let header = [
            "Rule",
            "Category",
            "File Path",
            "Line",
            "Severity",
            "Message",
            "Suggestion"
        ].joined(separator: ",")

        var csv = "\(header)\n"

        for issue in issues {
            for location in issue.locations {
                let row = [
                    CSVEscaping.escape(issue.ruleName.rawValue),
                    CSVEscaping.escape(String(describing: issue.ruleName.category)),
                    CSVEscaping.escape(location.filePath),
                    "\(location.lineNumber)",
                    issue.severity.rawValue,
                    CSVEscaping.escape(issue.message),
                    issue.suggestion.map { CSVEscaping.escape($0) } ?? ""
                ].joined(separator: ",")
                csv += row + "\n"
            }
        }

        return csv
    }
}

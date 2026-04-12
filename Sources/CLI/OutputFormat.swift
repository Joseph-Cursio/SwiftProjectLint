import ArgumentParser
import Core

/// Contract for types that render lint issues into a string report.
protocol IssueFormatterProtocol {
    func format(issues: [LintIssue]) -> String
}

/// The output format for lint results.
enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case text
    case json
    case html
    case csv

    /// Returns the formatter for this output format.
    var formatter: any IssueFormatterProtocol {
        switch self {
        case .text: return TextFormatter()
        case .json: return JSONFormatter()
        case .html: return HTMLFormatter()
        case .csv: return CSVFormatter()
        }
    }
}

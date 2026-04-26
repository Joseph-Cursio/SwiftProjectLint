import SwiftUI
import Core
import LintStudioUI

/// A reusable summary section displaying issue counts by severity.
///
/// Used in both `LintResultsView` and `FullScreenResultsView` to avoid
/// duplicating the summary layout.
struct IssueSummarySection: View {
    let issues: [LintIssue]

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Summary")
                        .font(.headline)
                    Spacer()
                }

                HStack(spacing: 16) {
                    StatisticBadge(
                        label: "Total Issues",
                        value: "\(issues.count)",
                        color: .primary
                    )
                    StatisticBadge(
                        label: "Errors",
                        value: "\(issues.filter { $0.severity == .error }.count)",
                        color: .red
                    )
                    StatisticBadge(
                        label: "Warnings",
                        value: "\(issues.filter { $0.severity == .warning }.count)",
                        color: .orange
                    )
                    StatisticBadge(
                        label: "Info",
                        value: "\(issues.filter { $0.severity == .info }.count)",
                        color: .blue
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    let issues: [LintIssue] = [
        LintIssue(
            severity: .error, message: "Error", filePath: "Foo.swift",
            lineNumber: 1, suggestion: nil, ruleName: .forceTry
        ),
        LintIssue(
            severity: .warning, message: "Warning", filePath: "Bar.swift",
            lineNumber: 2, suggestion: nil, ruleName: .catchWithoutHandling
        ),
        LintIssue(
            severity: .info, message: "Info", filePath: "Baz.swift",
            lineNumber: 3, suggestion: nil, ruleName: .dateNow
        )
    ]
    return List { IssueSummarySection(issues: issues) }
}

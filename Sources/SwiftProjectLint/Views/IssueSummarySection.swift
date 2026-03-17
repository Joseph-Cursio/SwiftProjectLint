import SwiftUI
import SwiftProjectLintCore

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
                    SummaryItem(
                        title: "Total Issues",
                        value: "\(issues.count)",
                        color: .primary
                    )
                    SummaryItem(
                        title: "Errors",
                        value: "\(issues.filter { $0.severity == .error }.count)",
                        color: .red
                    )
                    SummaryItem(
                        title: "Warnings",
                        value: "\(issues.filter { $0.severity == .warning }.count)",
                        color: .orange
                    )
                    SummaryItem(
                        title: "Info",
                        value: "\(issues.filter { $0.severity == .info }.count)",
                        color: .blue
                    )
                }
            }
            .padding(.vertical, 8)
        }
    }
}

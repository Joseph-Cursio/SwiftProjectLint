import SwiftUI
import Core

/// A full-screen view for displaying lint results with maximum space utilization.
struct FullScreenResultsView: View {
    let issues: [LintIssue]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            IssueListContent(issues: issues)
                .navigationTitle("Lint Results (\(issues.count) issues)")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    FullScreenResultsView(issues: [
        LintIssue(
            severity: .warning,
            message: "Duplicate state variable 'isLoading'",
            filePath: "ParentView.swift",
            lineNumber: 15,
            suggestion: "Move to a shared ObservableObject.",
            ruleName: .relatedDuplicateStateVariable
        )
    ])
}

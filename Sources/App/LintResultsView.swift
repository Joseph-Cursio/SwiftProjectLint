import SwiftUI
import Core

/// Shared list body used by both `LintResultsView` and `FullScreenResultsView`.
struct IssueListContent: View {
    let issues: [LintIssue]

    var body: some View {
        List {
            IssueSummarySection(issues: issues)

            Section {
                ForEach(issues.indices, id: \.self) { idx in
                    LintIssueRow(issue: issues[idx])
                    if idx != issues.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

/// A container view that manages state and presentation for lint results.
///
/// `LintResultsContainerView` owns the state for presenting the full screen results,
/// including the "Full Screen" button and sheet presentation. It renders the
/// stateless `LintResultsView` internally, which displays the lint issues list and summary.
///
/// - Parameters:
///   - issues: An array of `LintIssue` objects representing the issues to display.
struct LintResultsContainerView: View {
    let issues: [LintIssue]
    @State private var showingFullScreen = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with expand button
            HStack {
                Spacer()
                Button {
                    showingFullScreen = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        Text("Full Screen")
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(.rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Stateless lint results view
            LintResultsView(issues: issues)
        }
        .sheet(isPresented: $showingFullScreen) {
            FullScreenResultsView(issues: issues)
        }
        .frame(maxHeight: .infinity)
    }
}

/// A SwiftUI view that displays a list of lint issues found in a project.
///
/// `LintResultsView` presents each lint issue in a list, allowing users to
/// expand each item for more details and suggestions. It is designed to be
/// used in a navigation context and provides a clear overview of project
/// linting results.
///
/// - Parameters:
///   - issues: An array of `LintIssue` objects representing the issues to display.
///
/// The view uses `LintIssueRow` for each list entry, enabling details and
/// suggestions to be viewed via an expandable interface.
struct LintResultsView: View {
    let issues: [LintIssue]

    var body: some View {
        IssueListContent(issues: issues)
            .frame(minHeight: 200, maxHeight: .infinity)
            .layoutPriority(1)
    }
}

#Preview {
    let sampleIssues = [
        LintIssue(
            severity: .warning,
            message: "Duplicate state variable 'isLoading' found across multiple views",
            filePath: "/path/to/ParentView.swift",
            lineNumber: 15,
            suggestion: "Move 'isLoading' to a shared ObservableObject or use @EnvironmentObject for state sharing.",
            ruleName: .relatedDuplicateStateVariable
        ),
        LintIssue(
            severity: .error,
            message: "Missing @StateObject for ObservableObject property",
            filePath: "/path/to/ChildView.swift",
            lineNumber: 22,
            suggestion: "Use @StateObject instead of @ObservedObject for properties that should be owned by this view.",
            ruleName: .missingStateObject
        )
    ]

    LintResultsContainerView(issues: sampleIssues)
}

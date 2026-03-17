import SwiftUI
import SwiftProjectLintCore

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
                    .foregroundColor(.blue)
                    .cornerRadius(6)
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
        List {
            IssueSummarySection(issues: issues)

            // Issues section
            Section {
                ForEach(issues.indices, id: \.self) { idx in
                    LintIssueRow(issue: issues[idx])
                    if idx != issues.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .listStyle(PlainListStyle())
        .frame(minHeight: 200, maxHeight: .infinity)
        .layoutPriority(1)
    }
}

/// A SwiftUI view that displays a single lint issue in a row format, with expandable details.
///
/// `LintIssueRow` summarizes a lint issue with an icon indicating severity, a descriptive message,
/// and file location. Users can expand the row to reveal additional details and suggestions for resolving the issue.
///
/// - Parameters:
///   - issue: A `LintIssue` instance containing the severity, message, file path, line number, and an optional suggestion.
///
/// The row uses a chevron button to toggle expanded content, which displays the suggestion (if available)
/// and further file details. Severity is visually indicated using a color-coded SF Symbol.
/// The expansion is animated for a smooth user experience.
struct LintIssueRow: View {
    let issue: LintIssue
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                severityIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.message)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: true, vertical: true)
                        .lineLimit(nil)
                    if issue.locations.count == 1 {
                        Text("\(issue.locations[0].filePath):\(issue.locations[0].lineNumber)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(issue.locations.indices, id: \.self) { index in
                                let location = issue.locations[index]
                                Text("\(location.filePath):\(location.lineNumber)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.blue)
                }
            }

            if isExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        // Always show the full message, with multiline support
                        Text(issue.message)
                            .font(.body)
                            .foregroundColor(.primary)
                            .padding(.bottom, 4)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if let suggestion = issue.suggestion {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Suggestion:")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                                Text(suggestion)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .padding(.leading, 8)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Locations:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            ForEach(issue.locations.indices, id: \.self) { index in
                                let location = issue.locations[index]
                                Text("\(location.filePath):\(location.lineNumber)")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.leading, 24)
                }
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
    }

    private var severityIcon: some View {
        Image(systemName: severityIconName)
            .foregroundColor(severityColor)
            .font(.title2)
    }

    private var severityIconName: String {
        switch issue.severity {
        case .error:
            return "xmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private var severityColor: Color {
        switch issue.severity {
        case .error:
            return .red
        case .warning:
            return .orange
        case .info:
            return .blue
        }
    }
}

/// A summary item component for displaying statistics.
struct SummaryItem: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A full-screen view for displaying lint results with maximum space utilization.
struct FullScreenResultsView: View {
    let issues: [LintIssue]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                IssueSummarySection(issues: issues)

                // Issues section
                Section {
                    ForEach(issues.indices, id: \.self) { idx in
                        LintIssueRow(issue: issues[idx])
                        if idx != issues.count - 1 {
                            Divider()
                        }
                    }
                }
            }
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

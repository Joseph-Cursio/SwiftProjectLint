import Core
import SwiftUI

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
    private static let expandAnimationDuration: Double = 0.2

    let issue: LintIssue
    @State private var isExpanded: Bool

    init(issue: LintIssue, isExpanded: Bool = false) {
        self.issue = issue
        self._isExpanded = State(initialValue: isExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow
            if isExpanded {
                ExpandedIssueContent(issue: issue)
            }
        }
        .padding(.vertical, 4)
    }

    private var summaryRow: some View {
        HStack {
            severityIcon
            issueSummary
            Spacer()
            expandToggle
        }
    }

    private var issueSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(issue.message)
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: true, vertical: true)
                .lineLimit(nil)
            Text(issue.ruleName.rawValue)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fontDesign(.monospaced)
            locationLines
        }
    }

    @ViewBuilder
    private var locationLines: some View {
        if issue.locations.count == 1 {
            Text("\(issue.locations[0].filePath):\(issue.locations[0].lineNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(issue.locations.enumerated()), id: \.offset) { _, location in
                    Text("\(location.filePath):\(location.lineNumber)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var expandToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: Self.expandAnimationDuration)) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .foregroundStyle(.blue)
        }
        .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
    }

    private var severityIcon: some View {
        let style = IssueSeverityStyle(issue.severity)
        return Image(systemName: style.iconName)
            .foregroundStyle(style.color)
            .font(.title2)
            .accessibilityLabel(style.accessibilityLabel)
    }
}

// MARK: - Subviews

private struct ExpandedIssueContent: View {
    let issue: LintIssue

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 12) {
                messageBody
                if let suggestion = issue.suggestion {
                    suggestionSection(suggestion)
                }
                locationsSection
            }
            .padding(.leading, 24)
        }
        .frame(maxHeight: .infinity)
        .layoutPriority(1)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var messageBody: some View {
        Text(issue.message)
            .font(.body)
            .foregroundStyle(.primary)
            .padding(.bottom, 4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func suggestionSection(_ suggestion: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Suggestion:")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
            Text(suggestion)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(.leading, 8)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Locations:")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            ForEach(Array(issue.locations.enumerated()), id: \.offset) { _, location in
                Text("\(location.filePath):\(location.lineNumber)")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    let issue = LintIssue(
        severity: .warning,
        message: "Large view body detected",
        filePath: "ContentView.swift",
        lineNumber: 42,
        suggestion: "Extract subviews to reduce complexity.",
        ruleName: .fatView
    )
    return List { LintIssueRow(issue: issue, isExpanded: true) }
}

import SwiftUI
import LintStudioUI
import LintStudioCore

/// A sheet that shows a unified diff of YAML config changes before saving.
struct ConfigDiffPreviewSheet: View {
    let beforeYAML: String
    let afterYAML: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            UnifiedDiffContentView(
                before: beforeYAML,
                after: afterYAML,
                beforeLabel: "Current",
                afterLabel: "New"
            )
            Divider()
            footer
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 400, idealHeight: 500)
    }

    private var header: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
            Text("Review Configuration Changes")
                .font(.headline)
            Spacer()
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Save Changes", action: onConfirm)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}

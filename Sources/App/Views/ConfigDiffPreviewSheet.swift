import LintStudioCore
import LintStudioUI
import SwiftUI

/// A sheet that shows a unified diff of YAML config changes before saving.
struct ConfigDiffPreviewSheet: View {
    let beforeYAML: String
    let afterYAML: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DiffSheetHeader()
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

    /// Kept inline deliberately, and this is a decline rather than an oversight.
    ///
    /// Extracting it would hand a child `onConfirm` and `onCancel`. Both capture `viewModel` at
    /// the call site in `ContentView`, so they allocate a fresh context on every parent body run
    /// and the child value never compares equal — a child holding a capturing closure was measured
    /// to re-render exactly as often as the inlined property it replaced. There is no update for
    /// it to skip.
    ///
    /// The rule agrees now. Its capture gate saw a closure a property *creates* and not one it is
    /// *handed*; this property was one of the thirteen that closing the gap silenced.
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

/// The sheet's title bar, which depends on nothing.
///
/// A child with no inputs compares equal to itself on every parent update, so SwiftUI skips it —
/// measured at **0** re-renders over three changes, against 3 for the inlined property.
private struct DiffSheetHeader: View {
    var body: some View {
        HStack {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Review Configuration Changes")
                .font(.headline)
            Spacer()
        }
        .padding()
    }
}

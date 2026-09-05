import Core
import SwiftUI

/// How a severity is drawn: an icon, a colour, and the label VoiceOver reads.
///
/// Lifted out of `LintIssueRow`, where the three mappings lived as `private var`s returning
/// `String` and `Color`. They were reachable only by constructing the whole row and inspecting it,
/// which is what `LintIssueRowTests` does — one example test per severity, three views built to
/// check three constants.
///
/// The reason to lift them is not to save those three tests. It is that the laws worth stating
/// about this mapping are about the severities *as a set*, and no per-case example can express
/// them: that every case has a style at all, and that no two cases share an icon or a colour. A
/// severity row whose error and warning look identical is unreadable, and nothing in the code said
/// they had to differ.
/// `nonisolated` because the App target defaults to `MainActor` isolation and this is pure data
/// derived from an enum. Binding it to the main actor would mean a test could not build one off it,
/// which is the whole reason it was lifted out of the view.
nonisolated struct IssueSeverityStyle: Equatable {

    let iconName: String
    let color: Color
    let accessibilityLabel: String

    init(_ severity: IssueSeverity) {
        switch severity {
        case .error:
            self.iconName = "xmark.circle.fill"
            self.color = .red
            self.accessibilityLabel = "Error"

        case .warning:
            self.iconName = "exclamationmark.triangle.fill"
            self.color = .orange
            self.accessibilityLabel = "Warning"

        case .info:
            self.iconName = "info.circle.fill"
            self.color = .blue
            self.accessibilityLabel = "Info"
        }
    }
}

import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Control Missing Accessibility Label pattern.
///
/// Provides the pattern for detecting interactive controls (`Toggle`, `Button`)
/// created with an empty string label and no compensating `.accessibilityLabel`.
struct ControlMissingAccessibilityLabel: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .controlMissingAccessibilityLabel,
            visitor: ControlMissingAccessibilityLabelVisitor.self,
            severity: .warning,
            category: .accessibility,
            messageTemplate: "Control has an empty label and no .accessibilityLabel "
                + "— it is unlabeled for VoiceOver",
            suggestion: "Give the control a real label (Toggle(name, isOn:).labelsHidden() "
                + "keeps the layout), or add .accessibilityLabel(\"…\").",
            description: "Detects Toggle/Button created with an empty string label and no "
                + "compensating .accessibilityLabel, leaving the control unlabeled for VoiceOver."
        )
    }
}

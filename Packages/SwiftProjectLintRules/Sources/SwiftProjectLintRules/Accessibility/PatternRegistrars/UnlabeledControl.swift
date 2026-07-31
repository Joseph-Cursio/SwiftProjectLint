import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Unlabeled Control pattern.
///
/// Provides the pattern for detecting controls written with no label at all —
/// only `Slider` and `ProgressView` have label-less initializers. Opt-in.
struct UnlabeledControl: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .unlabeledControl,
            visitor: UnlabeledControlVisitor.self,
            severity: .warning,
            category: .accessibility,
            messageTemplate: "Control has no label — VoiceOver announces its value "
                + "and role but not what it controls",
            suggestion: "Add a label closure, e.g. Slider(value:in:) { Text(\"Volume\") }, "
                + "or add .accessibilityLabel(\"Volume\").",
            description: "Detects Slider and ProgressView written without a label. "
                + "Opt-in — enable via enabled_only."
        )
    }
}

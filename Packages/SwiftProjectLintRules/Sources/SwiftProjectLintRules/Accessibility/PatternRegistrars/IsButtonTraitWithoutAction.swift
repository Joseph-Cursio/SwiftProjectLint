import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the isButton Trait Without Action pattern.
///
/// Provides the pattern for detecting views that claim the `.isButton` accessibility
/// trait without supplying anything for the activate gesture to reach.
struct IsButtonTraitWithoutAction: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .isButtonTraitWithoutAction,
            visitor: IsButtonTraitWithoutActionVisitor.self,
            severity: .warning,
            category: .accessibility,
            messageTemplate: "The .isButton trait announces a button that cannot be activated. "
                + "Add an accessibility action, or use a Button.",
            suggestion: "Add .accessibilityAction { … }, or replace the view with a Button, "
                + "which carries the trait and the action together.",
            description: "Detects .accessibilityAddTraits(.isButton) on a view whose modifier "
                + "chain provides no activation path for assistive technology."
        )
    }
}

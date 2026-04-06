import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the God View Model pattern.
///
/// Detects view models with too many published/observed properties.
struct GodViewModel: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .godViewModel,
            visitor: GodViewModelVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "View model has too many published properties",
            suggestion: "Split into focused sub-view-models and compose "
                + "at the view level.",
            description: "Detects ObservableObject classes with >10 @Published "
                + "properties or @Observable classes with >15 var properties."
        )
    }
}

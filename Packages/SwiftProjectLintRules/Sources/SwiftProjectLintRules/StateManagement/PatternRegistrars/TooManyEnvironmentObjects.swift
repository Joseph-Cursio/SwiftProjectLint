import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the too-many-environment-objects pattern.
///
/// Detects SwiftUI views that depend on 4 or more @EnvironmentObject properties,
/// suggesting consolidation into fewer state containers.
struct TooManyEnvironmentObjects: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .tooManyEnvironmentObjects,
            visitor: TooManyEnvironmentObjectsVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "View '{viewName}' has {count} @EnvironmentObject properties — "
                + "consider consolidating into fewer state containers.",
            suggestion: "Combine related environment objects into a single app-state container "
                + "or split the view into smaller subviews with focused dependencies.",
            description: "Detects views with excessive @EnvironmentObject declarations that "
                + "suggest over-reliance on global state."
        )
    }
}

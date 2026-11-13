import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Related Duplicate State Variable pattern.
///
/// Cross-file analysis: a view and a child view it shows both own a `@State` or `@StateObject` of
/// the same name, so the child keeps a separate copy that will not follow the parent's changes.
struct RelatedDuplicateStateVariable: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .relatedDuplicateStateVariable,
            visitor: RelatedDuplicateStateVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "'{variableName}' is owned by both {childView} and its parent {parentViews}",
            suggestion: "Declare it `@Binding` in the child and pass the parent's `$` binding, or move "
                + "shared state into an observable object both views read.",
            description: "Detects a view and a child view it shows (in its body, a helper, a sheet or a "
                + "NavigationLink destination) that both own a @State or @StateObject of the same name, "
                + "in one file or across files."
        )
    }
}

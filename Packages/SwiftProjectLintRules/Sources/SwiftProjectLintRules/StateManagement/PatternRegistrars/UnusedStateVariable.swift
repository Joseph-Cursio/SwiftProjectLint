import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Unused State Variable pattern.
///
/// Flags a `private` or `fileprivate` `@State` whose name, as `x`, `$x` or `_x`, appears nowhere
/// else in its file.
struct UnusedStateVariable: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .unusedStateVariable,
            visitor: UnusedStateVariableVisitor.self,
            severity: .warning,
            category: .stateManagement,
            messageTemplate: "State variable '{variableName}' is declared but never used",
            suggestion: "Remove the unused state variable, or use it in the view.",
            description: "Detects a private or fileprivate @State whose name appears nowhere else in "
                + "its file, as itself, its $ projection or its _ storage."
        )
    }
}

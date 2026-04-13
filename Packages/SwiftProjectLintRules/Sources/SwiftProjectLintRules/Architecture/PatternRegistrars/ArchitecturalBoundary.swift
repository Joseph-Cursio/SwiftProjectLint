import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Registrar for the Architectural Boundary rule.
///
/// Flags import statements and type references that violate the layer policies
/// declared in `.swiftprojectlint.yml` under `architectural_layers:`.
///
/// This rule is a no-op when no layers are configured — it will never produce
/// output unless the user has added an `architectural_layers` block.
///
/// **Single-target apps only.** Modular projects that use separate SPM targets
/// get compiler-level enforcement for free; this rule adds nothing there.
struct ArchitecturalBoundary: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .architecturalBoundary,
            visitor: ArchitecturalBoundaryVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Architectural layer boundary violation",
            suggestion: "Move this dependency behind a layer-appropriate interface.",
            description: "Enforces import and type constraints per layer "
                + "defined in architectural_layers: in .swiftprojectlint.yml. "
                + "Designed for single-target apps — modular projects rely on the compiler."
        )
    }
}

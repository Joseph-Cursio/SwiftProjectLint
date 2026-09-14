import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Layer Dependency rule: a file in one architectural layer referencing a type
/// declared in a layer it has not been permitted to depend on.
struct LayerDependency: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .layerDependency,
            visitor: LayerDependencyVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Layer references a type from a layer it may not depend on",
            suggestion: "Depend on an abstraction this layer may use, or add the other layer to its "
                + "may_depend_on in .swiftprojectlint.yml.",
            description: "Checks references between the folders of architectural_layers: a layer that "
                + "sets may_depend_on may reference only its own types and those of the layers it lists. "
                + "Designed for single-target apps, where folders are the only boundary."
        )
    }
}

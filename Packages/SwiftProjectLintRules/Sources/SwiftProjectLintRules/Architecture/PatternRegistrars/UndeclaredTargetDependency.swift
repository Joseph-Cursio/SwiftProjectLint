import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Undeclared Target Dependency rule: a target importing a sibling target from
/// its own `Package.swift` without listing it in `dependencies:`.
struct UndeclaredTargetDependency: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .undeclaredTargetDependency,
            visitor: UndeclaredTargetDependencyVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Target imports a sibling target it does not declare as a dependency",
            suggestion: "Add the imported target to the importing target's dependencies in Package.swift.",
            description: "Compares each target's imports with the dependencies its Package.swift "
                + "declares, and reports an import of a sibling target that is not declared. "
                + "SwiftPM lets such an import compile while another dependency builds the module, "
                + "so it breaks when that unrelated edge is removed."
        )
    }
}

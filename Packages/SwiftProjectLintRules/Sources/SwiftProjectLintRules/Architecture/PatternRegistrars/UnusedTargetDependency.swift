import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Unused Target Dependency rule: a sibling target listed in `dependencies:`
/// that nothing in the declaring target imports.
struct UnusedTargetDependency: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .unusedTargetDependency,
            visitor: UnusedTargetDependencyVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Target declares a sibling-target dependency it never imports",
            suggestion: "Remove the dependency from Package.swift, or import it where it is used.",
            description: "Compares each target's declared dependencies on sibling targets with its "
                + "imports, and reports a dependency that no file imports, re-exports or names in "
                + "#externalMacro. A stale dependency costs rebuilds and misstates the package's layering."
        )
    }
}

import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Circular Dependency pattern.
///
/// Cross-file analysis that detects length-2 circular dependencies
/// between types (A→B→A).
struct CircularDependency: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .circularDependency,
            visitor: CircularDependencyVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Circular dependency detected: '{typeA}' \u{2194} '{typeB}'",
            suggestion: "Break the cycle with a protocol, mediator, or "
                + "by merging the types.",
            description: "Detects length-2 circular dependencies between "
                + "types via stored property references across files."
        )
    }
}

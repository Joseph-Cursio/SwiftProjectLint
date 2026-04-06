import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Nested Generic Complexity pattern.
///
/// Detects overly complex generic signatures. Opt-in rule.
struct NestedGenericComplexity: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .nestedGenericComplexity,
            visitor: NestedGenericComplexityVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Generic complexity exceeds threshold",
            suggestion: "Introduce typealiases to simplify complex "
                + "generic signatures.",
            description: "Detects functions with 4+ generic parameters, "
                + "generic nesting depth 3+, or where clauses with 4+ "
                + "constraints. Disabled by default."
        )
    }
}

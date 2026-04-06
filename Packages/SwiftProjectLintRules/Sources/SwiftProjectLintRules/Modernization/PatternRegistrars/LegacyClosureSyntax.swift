import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Legacy Closure Syntax pattern.
///
/// Detects closures with redundant explicit type annotations in inferrable
/// contexts. Opt-in rule.
struct LegacyClosureSyntax: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .legacyClosureSyntax,
            visitor: LegacyClosureSyntaxVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: "Closure parameter types can be inferred",
            suggestion: "Remove explicit type annotations and let Swift "
                + "infer them from context.",
            description: "Detects closures with explicit parameter types in "
                + "contexts where types are inferrable. Disabled by default."
        )
    }
}

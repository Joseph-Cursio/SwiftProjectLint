import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the Force Cast pattern.
///
/// Provides the pattern for detecting `as!` expressions that crash on a type mismatch.
struct ForceCast: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .forceCast,
            visitor: ForceCastVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "Force cast (as!) will crash on a type mismatch — use as? and handle the nil case",
            suggestion: "Use as? and handle the nil case, or restructure so the type is known statically.",
            description: "Detects force cast expressions that trap at runtime when the value is not "
                + "of the target type. Like try! and force unwrap, the trap is a fatal signal rather "
                + "than an error, so it cannot be caught by a test."
        )
    }
}

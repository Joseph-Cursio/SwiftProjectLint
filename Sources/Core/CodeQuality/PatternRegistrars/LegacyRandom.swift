import Foundation

/// A registrar for the Legacy Random pattern.
///
/// Provides the pattern for detecting legacy C random functions like `arc4random()`,
/// `arc4random_uniform()`, and `drand48()`.
struct LegacyRandom: PatternRegistrar {


    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .legacyRandom,
            visitor: LegacyRandomVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: "{name}() is a legacy C random function",
            suggestion: "Use Int.random(in:), Double.random(in:), or Bool.random() instead.",
            description: "Detects legacy C random functions (arc4random, arc4random_uniform, drand48) "
                + "that should be replaced with Swift's type-safe random APIs."
        )
    }
}

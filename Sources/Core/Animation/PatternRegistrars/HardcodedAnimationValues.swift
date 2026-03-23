import Foundation

/// A registrar for the hardcoded animation values pattern.
///
/// Provides the pattern for detecting magic number literals in animation factory calls.
struct HardcodedAnimationValues: PatternRegistrar {


    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .hardcodedAnimationValues,
            visitor: HardcodedAnimationValuesVisitor.self,
            severity: .info,
            category: .animation,
            messageTemplate: "Hardcoded numeric literal in animation factory call. " +
                "Magic numbers make animations hard to maintain.",
            suggestion: "Extract animation timing values to named constants for consistency and maintainability.",
            description: "Detects numeric literals passed to animation factory parameters like duration:, " +
                "response:, dampingFraction:, bounce:, etc."
        )
    }
}

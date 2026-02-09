import Foundation

/// A registrar for the excessive spring animations pattern.
///
/// This struct defines the metadata for the excessive spring animations rule
/// and registers it with the `SourcePatternRegistry`. The pattern detects
/// views that use too many spring animations, which can degrade performance.
struct AnimationPerformancePatternRegistrar: PatternRegistrar {

    var pattern: SyntaxPattern {
        return SyntaxPattern(
            name: .excessiveSpringAnimations,
            visitor: AnimationPerformanceVisitor.self,
            severity: .warning,
            category: .animation,
            messageTemplate: "Excessive spring animations detected in view. " +
                "Spring animations are computationally expensive.",
            suggestion: "Consider reducing the number of spring animations or combining them " +
                "using a single withAnimation(.spring()) block.",
            description: "Detects views with more than 3 spring animation calls, " +
                "which can cause performance degradation."
        )
    }
}

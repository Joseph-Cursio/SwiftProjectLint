import Foundation

/// A registrar for animation performance patterns.
///
/// This struct defines the metadata for animation performance rules
/// and registers them with the `SourcePatternRegistry`. It provides
/// patterns for excessive spring animations, long animation durations,
/// and animations in high-frequency update contexts.
struct AnimationPerformance: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [
            SyntaxPattern(
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
            ),
            SyntaxPattern(
                name: .animationInHighFrequencyUpdate,
                visitor: AnimationPerformanceVisitor.self,
                severity: .warning,
                category: .animation,
                messageTemplate: "Animation modifier used near a high-frequency callback. " +
                    "This can cause excessive re-rendering.",
                suggestion: "Move the animation to a more targeted location or use " +
                    "explicit state-driven animations with withAnimation.",
                description: "Detects .animation() modifiers chained near onReceive, onChange, " +
                    "or task callbacks that may fire frequently."
            ),
            SyntaxPattern(
                name: .longAnimationDuration,
                visitor: AnimationPerformanceVisitor.self,
                severity: .info,
                category: .animation,
                messageTemplate: "Animation duration exceeds 2 seconds. " +
                    "Long animations can feel sluggish to users.",
                suggestion: "Consider reducing the animation duration to under 2 seconds " +
                    "for a more responsive user experience.",
                description: "Detects animation factory calls with duration parameters " +
                    "exceeding 2.0 seconds."
            )
        ]
    }

    var pattern: SyntaxPattern { patterns[0] }
}

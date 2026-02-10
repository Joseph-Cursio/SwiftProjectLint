import Foundation

/// A registrar for `withAnimation`-related patterns.
///
/// This struct defines the metadata for rules detecting anti-patterns
/// in `withAnimation` usage, including calling it inside `onAppear`
/// and using it without any state mutations.
struct WithAnimationPatternRegistrar: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [
            SyntaxPattern(
                name: .withAnimationInOnAppear,
                visitor: WithAnimationVisitor.self,
                severity: .warning,
                category: .animation,
                messageTemplate: "withAnimation used inside onAppear. " +
                    "This can cause unexpected animations when the view first appears.",
                suggestion: "Consider using .animation() modifier with a value parameter " +
                    "or .onAppear with explicit state changes instead.",
                description: "Detects withAnimation calls inside onAppear closures, " +
                    "which can cause jarring animations on view appearance."
            ),
            SyntaxPattern(
                name: .animationWithoutStateChange,
                visitor: WithAnimationVisitor.self,
                severity: .info,
                category: .animation,
                messageTemplate: "withAnimation block does not contain any state mutations. " +
                    "The animation will have no effect.",
                suggestion: "Add state mutations inside the withAnimation closure, " +
                    "or remove the withAnimation wrapper if no animation is needed.",
                description: "Detects withAnimation closures that contain no assignments, " +
                    "compound assignments, or toggle() calls."
            )
        ]
    }

    var pattern: SyntaxPattern { patterns[0] }
}

import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for animation hierarchy patterns.
///
/// Provides patterns for conflicting animation modifiers and default animation curve usage.
struct AnimationHierarchy: PatternRegistrarProtocol {

    var patterns: [SyntaxPattern] {
        [
            SyntaxPattern(
                name: .conflictingAnimations,
                visitor: AnimationHierarchyVisitor.self,
                severity: .warning,
                category: .animation,
                messageTemplate: "Two .animation() modifiers target the same value. " +
                    "Only the outermost animation takes effect.",
                suggestion: "Remove the redundant .animation() modifier and keep only one animation for each value.",
                description: "Detects chained .animation() modifiers that both target the same value: argument, " +
                    "causing the inner animation to be silently ignored."
            ),
            SyntaxPattern(
                name: .defaultAnimationCurve,
                visitor: AnimationHierarchyVisitor.self,
                severity: .info,
                category: .animation,
                messageTemplate: "Using .animation(.default, ...) relies on the system default curve.",
                suggestion: "Specify an explicit animation curve such as .easeInOut, .spring(), or .linear.",
                description: "Detects use of .animation(.default, value:) which relies on the system default " +
                    "animation curve and may produce inconsistent behavior."
            )
        ]
    }

    var pattern: SyntaxPattern { patterns[0] }
}

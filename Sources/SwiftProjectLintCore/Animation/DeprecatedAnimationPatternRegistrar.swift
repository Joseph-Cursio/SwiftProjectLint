import Foundation

/// A registrar for the deprecated animation pattern.
///
/// This struct is responsible for defining the metadata for the deprecated animation rule
/// and registering it with the `SourcePatternRegistry`. The pattern is designed to detect
/// the usage of the deprecated `.animation()` modifier in SwiftUI code.
struct DeprecatedAnimationPatternRegistrar: PatternRegistrar {

    /// The syntax pattern to be registered.
    ///
    /// This pattern includes the rule's identifier, severity, and a message template
    /// that will be displayed to the user when a violation is detected. The `visitor`
    /// property is set to `DeprecatedAnimationVisitor.self`, which is the SwiftSyntax
    /// visitor responsible for identifying the deprecated modifier.
    var pattern: SyntaxPattern {
        return SyntaxPattern(
            name: .deprecatedAnimation,
            visitor: DeprecatedAnimationVisitor.self,
            severity: .warning,
            category: .animation,
            messageTemplate: "The `.animation()` modifier is deprecated. Use `.animation(_:value:)` instead.",
            suggestion: "Replace the deprecated `.animation()` modifier with the value-based version to explicitly control animations.",
            description: "Detects usage of the deprecated .animation() modifier without a value parameter."
        )
    }
}

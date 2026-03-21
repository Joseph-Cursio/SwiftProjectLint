import Foundation

/// A registrar for the Date.now pattern.
///
/// Provides the pattern for detecting `Date()` calls that should use `Date.now` instead.
struct DateNowPatternRegistrar: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .dateNow,
            visitor: DateNowVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Use Date.now instead of Date()",
            suggestion: "Replace Date() with .now for clarity.",
            description: "Detects Date() initializer calls that can be replaced with the "
                + "more concise Date.now property (available since iOS 15 / macOS 12)."
        )
    }
}

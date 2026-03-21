import Foundation

/// A registrar for the CF Absolute Time pattern.
///
/// Provides the pattern for detecting `CFAbsoluteTimeGetCurrent()` calls that should use
/// modern Swift alternatives.
struct CFAbsoluteTimePatternRegistrar: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .cfAbsoluteTime,
            visitor: CFAbsoluteTimeVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: "CFAbsoluteTimeGetCurrent() is a legacy Core Foundation API",
            suggestion: "Use ContinuousClock for timing measurements or Date.now for timestamps.",
            description: "Detects CFAbsoluteTimeGetCurrent() calls that can be replaced with "
                + "ContinuousClock for timing or Date.now for timestamps."
        )
    }
}

import Foundation

/// A registrar for the hardcoded font size pattern.
///
/// Provides the pattern for detecting literal numeric sizes in `.font(.system(size:))` calls
/// that bypass Dynamic Type.
struct HardcodedFontSizePatternRegistrar: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .hardcodedFontSize,
            visitor: HardcodedFontSizeVisitor.self,
            severity: .warning,
            category: .accessibility,
            messageTemplate: "Hardcoded font size bypasses Dynamic Type. "
                + "Use semantic text styles (.title, .body, etc.) for accessibility.",
            suggestion: "Replace .font(.system(size: N)) with a semantic style like .font(.title), "
                + "or use @ScaledMetric for custom sizes.",
            description: "Detects .font(.system(size:)) calls with literal numeric values "
                + "that bypass Dynamic Type accessibility scaling."
        )
    }
}

import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the hardcoded font size pattern.
///
/// Provides the pattern for detecting literal numeric sizes in `.font(.system(size:))` and
/// `.font(.custom(_:size:))` calls that bypass Dynamic Type.
struct HardcodedFontSize: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .hardcodedFontSize,
            visitor: HardcodedFontSizeVisitor.self,
            severity: .warning,
            category: .accessibility,
            messageTemplate: "Hardcoded font size bypasses Dynamic Type. "
                + "Use semantic text styles (.title, .body, etc.) for accessibility.",
            suggestion: "Replace .font(.system(size: N)) with a semantic style like .font(.title). "
                + "For a custom face, add a relativeTo: anchor, or use @ScaledMetric.",
            description: "Detects .font(.system(size:)) and .font(.custom(_:size:)) calls with "
                + "literal numeric values that bypass Dynamic Type accessibility scaling."
        )
    }
}

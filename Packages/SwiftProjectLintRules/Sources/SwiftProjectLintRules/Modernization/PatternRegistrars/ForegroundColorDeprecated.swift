import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Foreground Color Deprecated pattern.
///
/// Provides the pattern for detecting `.foregroundColor()` modifier usage that was
/// deprecated in iOS 17 in favour of `.foregroundStyle()`.
struct ForegroundColorDeprecated: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .foregroundColorDeprecated,
            visitor: ForegroundColorDeprecatedVisitor.self,
            severity: .warning,
            category: .modernization,
            messageTemplate: ".foregroundColor() is deprecated in iOS 17",
            suggestion: "Use .foregroundStyle() instead — it accepts any ShapeStyle including gradients and materials.",
            description: "Detects .foregroundColor() modifier usage deprecated in iOS 17. "
                + ".foregroundStyle() is the modern replacement and accepts any ShapeStyle, "
                + "enabling gradients, materials, and hierarchical styles."
        )
    }
}

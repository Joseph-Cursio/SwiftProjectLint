import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Corner Radius Deprecated pattern.
///
/// Provides the pattern for detecting `.cornerRadius()` modifier usage that was
/// deprecated in iOS 17 in favour of `.clipShape(.rect(cornerRadius:))`.
struct CornerRadiusDeprecated: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .cornerRadiusDeprecated,
            visitor: CornerRadiusDeprecatedVisitor.self,
            severity: .warning,
            category: .modernization,
            messageTemplate: ".cornerRadius() is deprecated in iOS 17",
            suggestion: "Use .clipShape(.rect(cornerRadius:)) or .clipShape(RoundedRectangle(cornerRadius:)) instead.",
            description: "Detects .cornerRadius() modifier usage deprecated in iOS 17. "
                + ".clipShape(.rect(cornerRadius:)) is the modern replacement, enabling the continuous "
                + "corner style and composing cleanly with other shape-based modifiers."
        )
    }
}

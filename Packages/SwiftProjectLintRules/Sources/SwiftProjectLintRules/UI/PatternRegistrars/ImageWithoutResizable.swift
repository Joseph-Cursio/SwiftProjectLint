import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Image Without Resizable pattern.
///
/// Detects `Image(...)` with `.frame()` but no `.resizable()` in the
/// modifier chain.
struct ImageWithoutResizable: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .imageWithoutResizable,
            visitor: ImageWithoutResizableVisitor.self,
            severity: .info,
            category: .uiPatterns,
            messageTemplate: "Image with .frame() but no .resizable()",
            suggestion: "Add .resizable() before .frame() to allow "
                + "the image to scale.",
            description: "Detects Image views with .frame() but no "
                + ".resizable(), which renders at intrinsic size."
        )
    }
}

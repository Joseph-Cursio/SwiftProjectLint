import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Legacy Image Renderer pattern.
///
/// Detects `UIGraphicsImageRenderer` usage that should use SwiftUI's
/// `ImageRenderer` (iOS 16+).
struct LegacyImageRenderer: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .legacyImageRenderer,
            visitor: LegacyImageRendererVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: "UIGraphicsImageRenderer is the legacy UIKit rendering API",
            suggestion: "Use SwiftUI's ImageRenderer instead (requires iOS 16+).",
            description: "Detects UIGraphicsImageRenderer usage that can use "
                + "SwiftUI's ImageRenderer."
        )
    }
}

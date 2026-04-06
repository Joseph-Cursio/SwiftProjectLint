import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the GeometryReader Overuse pattern.
///
/// Detects `GeometryReader` usage that may be replaceable with
/// `containerRelativeFrame()` or `visualEffect()` (iOS 17+).
/// Opt-in rule — disabled by default.
struct GeometryReaderOveruse: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .geometryReaderOveruse,
            visitor: GeometryReaderOveruseVisitor.self,
            severity: .info,
            category: .performance,
            messageTemplate: "GeometryReader eagerly consumes all available space",
            suggestion: "Use containerRelativeFrame() or visualEffect() "
                + "instead (iOS 17+).",
            description: "Detects GeometryReader usage that may be replaceable "
                + "with modern iOS 17 layout APIs. Disabled by default."
        )
    }
}

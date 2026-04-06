import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the ScrollView showsIndicators pattern.
///
/// Detects `ScrollView(showsIndicators:)` usage that should use the modern
/// `.scrollIndicators(.hidden)` modifier.
struct ScrollViewShowsIndicators: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .scrollViewShowsIndicators,
            visitor: ScrollViewShowsIndicatorsVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: "ScrollView(showsIndicators:) is the legacy scroll indicator API",
            suggestion: "Use .scrollIndicators(.hidden) modifier instead "
                + "(requires iOS 16+).",
            description: "Detects ScrollView(showsIndicators:) usage that can use "
                + "the .scrollIndicators() modifier from iOS 16."
        )
    }
}

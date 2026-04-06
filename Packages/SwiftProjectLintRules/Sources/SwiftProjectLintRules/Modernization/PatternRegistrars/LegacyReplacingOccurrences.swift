import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Legacy Replacing Occurrences pattern.
///
/// Detects `.replacingOccurrences(of:with:)` calls that should use the modern
/// `.replacing(_:with:)` API introduced in Swift 5.7.
struct LegacyReplacingOccurrences: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .legacyReplacingOccurrences,
            visitor: LegacyReplacingOccurrencesVisitor.self,
            severity: .info,
            category: .modernization,
            messageTemplate: ".replacingOccurrences(of:with:) is the legacy Foundation API",
            suggestion: "Use .replacing(\"old\", with: \"new\") instead (requires iOS 16+/Swift 5.7).",
            description: "Detects .replacingOccurrences(of:with:) calls that can use "
                + "the modern .replacing(_:with:) API from Swift 5.7."
        )
    }
}

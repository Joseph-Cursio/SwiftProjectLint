import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the modifier order pattern.
///
/// Detects incorrect SwiftUI modifier ordering where the visual result
/// differs from the developer's likely intent (e.g., background applied
/// before clipShape, so the background isn't clipped).
struct ModifierOrder: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .modifierOrderIssue,
            visitor: ModifierOrderVisitor.self,
            severity: .warning,
            category: .uiPatterns,
            messageTemplate: ".{before}() applied before .{after}() — {reason}.",
            suggestion: "Move .{before}() after .{after}() so the modifier applies correctly.",
            description: "Detects incorrect SwiftUI modifier ordering that causes "
                + "unintended visual results."
        )
    }
}

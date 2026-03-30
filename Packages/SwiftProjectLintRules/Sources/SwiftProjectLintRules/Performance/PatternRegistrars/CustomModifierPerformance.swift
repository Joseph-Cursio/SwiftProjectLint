import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the custom modifier performance pattern.
///
/// Detects expensive operations (sorted, filter, map, etc.) inside custom
/// ViewModifier body implementations that run on every view update.
struct CustomModifierPerformance: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .customModifierPerformance,
            visitor: CustomModifierPerformanceVisitor.self,
            severity: .warning,
            category: .performance,
            messageTemplate: "Expensive operation in ViewModifier '{modifierName}' body: {operation}.",
            suggestion: "Move expensive operations outside the body(content:) method "
                + "or precompute values in stored properties.",
            description: "Detects expensive operations inside custom ViewModifier body "
                + "implementations that run on every view update."
        )
    }
}

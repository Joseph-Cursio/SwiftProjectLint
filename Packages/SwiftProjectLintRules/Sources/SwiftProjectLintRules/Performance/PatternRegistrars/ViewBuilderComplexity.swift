import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the ViewBuilder complexity pattern.
///
/// Detects @ViewBuilder functions and computed properties that are too large,
/// suggesting extraction into smaller subviews.
struct ViewBuilderComplexity: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .viewBuilderComplexity,
            visitor: ViewBuilderComplexityVisitor.self,
            severity: .warning,
            category: .performance,
            messageTemplate: "@ViewBuilder '{name}' is too complex "
                + "({lineCount} lines, {statementCount} statements) — consider splitting.",
            suggestion: "Extract parts of this @ViewBuilder into separate subviews "
                + "or helper functions for better readability and performance.",
            description: "Detects @ViewBuilder functions or computed properties that exceed "
                + "30 lines or 15 statements."
        )
    }
}

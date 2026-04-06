import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the Computed Property View pattern.
///
/// Detects computed properties returning `some View` inside View types.
struct ComputedPropertyView: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .computedPropertyView,
            visitor: ComputedPropertyViewVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Computed property '{propertyName}' returns "
                + "'some View' — extract into a separate View struct",
            suggestion: "Move the computed property into its own struct "
                + "conforming to View",
            description: "Detects computed properties returning some View "
                + "inside View types where a separate View struct would "
                + "give SwiftUI a stable identity boundary"
        )
    }
}

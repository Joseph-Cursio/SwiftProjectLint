import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the SwiftProjectLint suppression comment pattern.
///
/// Detects `swiftprojectlint:disable`, `swiftprojectlint:disable:next`,
/// and `swiftprojectlint:disable:this` comments that suppress rules.
struct SwiftProjectLintSuppression: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .swiftprojectlintSuppression,
            visitor: SwiftProjectLintSuppressionVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "SwiftProjectLint suppression: {directive} {rule}",
            suggestion: "Fix the underlying issue instead of suppressing the rule.",
            description: "Detects swiftprojectlint:disable, disable:next, and "
                + "disable:this comments that suppress SwiftProjectLint rules."
        )
    }
}

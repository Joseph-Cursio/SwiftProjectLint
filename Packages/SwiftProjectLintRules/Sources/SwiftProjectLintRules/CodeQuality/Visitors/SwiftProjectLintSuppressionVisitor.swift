import SwiftProjectLintModels

/// A SwiftSyntax visitor that detects SwiftProjectLint suppression comments.
///
/// Flags `// swiftprojectlint:disable <rule>` (block) and the `:next` and
/// `:this` line-scoped variants. Multiple rules on one line each produce a
/// separate issue. Traversal and parsing live in ``SuppressionVisitorBase``.
final class SwiftProjectLintSuppressionVisitor: SuppressionVisitorBase {

    override var directives: [String] {
        [
            "swiftprojectlint:disable:next",
            "swiftprojectlint:disable:this",
            "swiftprojectlint:disable"
        ]
    }

    override var toolName: String { "SwiftProjectLint" }

    override var suggestion: String {
        "Fix the underlying issue instead of suppressing the rule."
    }

    override var ruleIdentifier: RuleIdentifier { .swiftprojectlintSuppression }
}

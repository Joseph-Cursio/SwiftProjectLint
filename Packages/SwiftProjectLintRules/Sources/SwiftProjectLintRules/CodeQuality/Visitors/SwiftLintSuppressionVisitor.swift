import SwiftProjectLintModels

/// A SwiftSyntax visitor that detects SwiftLint suppression comments in source code.
///
/// Flags `// swiftlint:disable <rule>` (block) and the `:next`, `:this`, and
/// `:previous` line-scoped variants. Multiple rules on one line each produce a
/// separate issue. Traversal and parsing live in ``SuppressionVisitorBase``.
final class SwiftLintSuppressionVisitor: SuppressionVisitorBase {

    override var directives: [String] {
        [
            "swiftlint:disable:next",
            "swiftlint:disable:this",
            "swiftlint:disable:previous",
            "swiftlint:disable"
        ]
    }

    override var toolName: String { "SwiftLint" }

    override var suggestion: String {
        "Fix the underlying issue instead of suppressing the SwiftLint rule."
    }

    override var ruleIdentifier: RuleIdentifier { .swiftlintSuppression }
}

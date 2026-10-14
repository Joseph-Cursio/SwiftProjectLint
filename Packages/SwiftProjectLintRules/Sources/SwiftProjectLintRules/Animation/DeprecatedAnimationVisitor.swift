import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects the usage of the deprecated `.animation()` modifier.
///
/// This visitor walks the Swift syntax tree and identifies function calls to `.animation()`
/// that have a single argument, which is the deprecated form of the modifier.
///
/// ## Deprecated Usage
///
/// The deprecated `.animation()` modifier accepts a single `Animation` argument:
///
/// ```swift
/// .animation(.default)
/// ```
///
/// ## Recommended Usage
///
/// The recommended replacement is the two-argument version, which includes a `value` parameter
/// to explicitly control when the animation is triggered:
///
/// ```swift
/// .animation(.default, value: myValue)
/// ```
///
/// This visitor flags the single-argument version as a lint issue.
final class DeprecatedAnimationVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Ensure the function call is a member access expression (e.g., `view.animation(...)`)
        // and the deprecated `.animation()` modifier. Both come before the base's text, which
        // costs the base's size: every call in a member chain has the rest of the chain as
        // its base, so building it first made the chain cost the square of its length.
        guard let calledExpression = node.calledExpression.as(MemberAccessExprSyntax.self),
              let base = calledExpression.base,
              calledExpression.declName.baseName.text == "animation",
              node.arguments.count == 1,
              !base.description.hasSuffix("Binding") else {
            return .visitChildren
        }

        addIssue(node: Syntax(node))
        return .visitChildren
    }
}

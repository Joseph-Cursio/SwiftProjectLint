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
        guard let calledExpression = node.calledExpression.as(MemberAccessExprSyntax.self),
              let base = calledExpression.base,
              !base.description.hasSuffix("Binding") else {
            return .visitChildren
        }

        // Check if the function call is the deprecated `.animation()` modifier
        if calledExpression.declName.baseName.text == "animation", node.arguments.count == 1 {
            addIssue(node: Syntax(node))
        }

        return .visitChildren
    }
}

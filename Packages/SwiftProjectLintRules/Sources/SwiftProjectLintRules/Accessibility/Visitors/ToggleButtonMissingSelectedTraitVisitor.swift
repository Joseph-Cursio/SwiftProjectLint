import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `Button` views whose label contains a ternary expression (suggesting
/// visual state toggling) but that lack `.accessibilityAddTraits` to communicate
/// the selected/unselected state to VoiceOver.
///
/// Flagged:
/// ```swift
/// Button(action: { selected.toggle() }) {
///     Image(systemName: selected ? "circle.fill" : "circle")
/// }
/// // Missing .accessibilityAddTraits(selected ? .isSelected : [])
/// ```
final class ToggleButtonMissingSelectedTraitVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isTestOrFixtureFile() { return .visitChildren }
        detectMissingSelectedTrait(node)
        return .visitChildren
    }

    private func detectMissingSelectedTrait(_ node: FunctionCallExprSyntax) {
        // Must be a Button call
        guard let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
              calledExpr.baseName.text == "Button" else { return }

        // Skip buttons hidden from VoiceOver
        if AccessibilityTreeTraverser.hasAccessibilityModifier(
            in: node, modifierName: "accessibilityHidden"
        ) { return }

        // Check if the button body contains a ternary expression
        guard containsTernary(in: node) else { return }

        // Already has accessibilityAddTraits — nothing to flag
        if AccessibilityTreeTraverser.hasAccessibilityModifier(
            in: node, modifierName: "accessibilityAddTraits"
        ) { return }

        addIssue(
            severity: .warning,
            message: "Button with conditional appearance may need "
                + ".accessibilityAddTraits to communicate selected state",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Add .accessibilityAddTraits(isSelected ? .isSelected : []) "
                + "so VoiceOver announces the selection state.",
            ruleName: .toggleButtonMissingSelectedTrait
        )
    }

    /// Returns true if the button's label closure or arguments contain
    /// a ternary expression, suggesting visual state changes.
    private func containsTernary(in node: FunctionCallExprSyntax) -> Bool {
        // Check trailing closure (the label body)
        if let trailing = node.trailingClosure {
            if hasTernary(in: Syntax(trailing)) {
                return true
            }
        }

        // Check label: argument closure
        for argument in node.arguments {
            if let closure = argument.expression.as(ClosureExprSyntax.self),
               hasTernary(in: Syntax(closure)) {
                return true
            }
        }

        // Check additional trailing closures (e.g., Button { action } label: { ... })
        for element in node.additionalTrailingClosures
            where hasTernary(in: Syntax(element.closure)) {
            return true
        }

        return false
    }

    /// Recursively checks whether a syntax subtree contains a TernaryExpr.
    private func hasTernary(in syntax: Syntax) -> Bool {
        // Parser produces UnresolvedTernaryExprSyntax (operator precedence
        // is not resolved at parse time), so check for that type.
        if syntax.is(UnresolvedTernaryExprSyntax.self) {
            return true
        }
        for child in syntax.children(viewMode: .sourceAccurate)
            where hasTernary(in: child) {
            return true
        }
        return false
    }
}

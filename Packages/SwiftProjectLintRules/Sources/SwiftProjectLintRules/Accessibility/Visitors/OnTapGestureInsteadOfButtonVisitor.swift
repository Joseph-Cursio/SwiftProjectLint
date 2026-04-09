import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Detects `.onTapGesture { }` calls that should be `Button` instead,
/// and verifies that allowed multi-tap / location-aware gestures have
/// accessibility traits so VoiceOver can discover them.
///
/// The zero-argument form of `onTapGesture` bypasses SwiftUI's button semantics — it provides
/// no implicit accessibility trait, no keyboard/pointer focus, and no haptic feedback. Calls
/// with `count:` > 1 or a location-aware closure parameter are allowed since they have
/// legitimate uses that `Button` cannot replace, but they still need accessibility traits.
class OnTapGestureInsteadOfButtonVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isTestOrFixtureFile() { return .visitChildren }
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "onTapGesture" else {
            return .visitChildren
        }

        // Check for allowed forms: count > 1, coordinateSpace, or closure with parameters
        let isMultiTap = hasMultiTapCount(node)
        let isLocationAware = hasLocationAwareness(node)

        if isMultiTap || isLocationAware {
            // Allowed use — but check for accessibility traits
            checkAccessibilityTraits(on: node)
            return .visitChildren
        }

        addIssue(
            severity: .warning,
            message: "Prefer Button over .onTapGesture — "
                + "onTapGesture bypasses accessibility traits, keyboard focus, and haptic feedback",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Replace .onTapGesture { ... } with a Button",
            ruleName: .onTapGestureInsteadOfButton
        )
        return .visitChildren
    }

    // MARK: - Allowed form detection

    private func hasMultiTapCount(_ node: FunctionCallExprSyntax) -> Bool {
        guard let countArg = node.arguments.first(where: { $0.label?.text == "count" }),
              let intExpr = countArg.expression.as(IntegerLiteralExprSyntax.self),
              let count = Int(intExpr.literal.text) else { return false }
        return count > 1
    }

    private func hasLocationAwareness(_ node: FunctionCallExprSyntax) -> Bool {
        if node.arguments.contains(where: { $0.label?.text == "coordinateSpace" }) {
            return true
        }
        if let trailingClosure = node.trailingClosure,
           let signature = trailingClosure.signature,
           hasClosureParameters(signature) {
            return true
        }
        return false
    }

    // MARK: - Accessibility check for allowed gestures

    /// When onTapGesture is allowed (multi-tap or location-aware), verify that
    /// the modifier chain includes accessibilityAddTraits or accessibilityLabel
    /// so VoiceOver users can discover the gesture.
    private func checkAccessibilityTraits(on node: FunctionCallExprSyntax) {
        let hasTraits = AccessibilityTreeTraverser.hasAccessibilityModifier(
            in: node, modifierName: "accessibilityAddTraits"
        )
        let hasLabel = AccessibilityTreeTraverser.hasAccessibilityModifier(
            in: node, modifierName: "accessibilityLabel"
        )

        if !hasTraits && !hasLabel {
            addIssue(
                severity: .info,
                message: "onTapGesture with count or location is invisible to VoiceOver "
                    + "— add .accessibilityAddTraits(.isButton) and .accessibilityLabel()",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Add .accessibilityAddTraits(.isButton) and "
                    + ".accessibilityLabel(\"description\") to make this gesture discoverable",
                ruleName: .onTapGestureMissingAccessibility
            )
        }
    }

    /// Returns true if the closure signature declares at least one parameter.
    private func hasClosureParameters(_ signature: ClosureSignatureSyntax) -> Bool {
        guard let paramClause = signature.parameterClause else { return false }
        switch paramClause {
        case .simpleInput(let params):
            return params.isEmpty == false
        case .parameterClause(let clause):
            return clause.parameters.isEmpty == false
        }
    }
}

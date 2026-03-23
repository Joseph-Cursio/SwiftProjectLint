import SwiftSyntax

/// A SwiftSyntax visitor that detects animation hierarchy anti-patterns.
///
/// Detects two patterns based on the `pattern.name` gate:
/// - `.defaultAnimationCurve`: `.animation(.default, value:)` usage
/// - `.conflictingAnimations`: Two `.animation(_, value: x)` modifiers with the same `value:` argument chained on the same view
final class AnimationHierarchyVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        switch pattern.name {
        case .defaultAnimationCurve:
            detectDefaultAnimationCurve(node)
        case .conflictingAnimations:
            detectConflictingAnimations(node)
        default:
            break
        }
        return .visitChildren
    }

    // MARK: - Default Animation Curve

    private func detectDefaultAnimationCurve(_ node: FunctionCallExprSyntax) {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "animation" else { return }

        // Check if the first non-labeled argument is `.default`
        guard let firstArg = node.arguments.first(where: { $0.label == nil }),
              let argMemberAccess = firstArg.expression.as(MemberAccessExprSyntax.self),
              argMemberAccess.declName.baseName.text == "default" else { return }

        addIssue(
            severity: .info,
            message: "Using .animation(.default, ...) relies on the system default animation curve. " +
                "This can produce unexpected animations when the system default changes.",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Specify an explicit animation curve such as .easeInOut, .spring(), or .linear " +
                "to ensure consistent animation behavior.",
            ruleName: .defaultAnimationCurve
        )
    }

    // MARK: - Conflicting Animations

    private func detectConflictingAnimations(_ node: FunctionCallExprSyntax) {
        // Check outer call is an animation modifier
        guard let outerValue = animationValueArgText(node) else { return }

        // Check if the base expression is itself an animation modifier call
        guard let outerMemberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              let innerCall = outerMemberAccess.base?.as(FunctionCallExprSyntax.self),
              let innerValue = animationValueArgText(innerCall) else { return }

        // If both animation modifiers target the same value, flag as conflicting
        guard outerValue == innerValue else { return }

        addIssue(
            severity: .warning,
            message: "Conflicting animations detected: two .animation() modifiers " +
                "both target 'value: \(outerValue)'. Only the outermost animation will take effect.",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Remove the redundant .animation() modifier and keep only one animation for each value.",
            ruleName: .conflictingAnimations
        )
    }

    /// Extracts the `value:` argument text from an `.animation(_, value:)` call.
    private func animationValueArgText(_ node: FunctionCallExprSyntax) -> String? {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "animation" else { return nil }
        return node.arguments.first(where: { $0.label?.text == "value" })?.expression.trimmedDescription
    }
}

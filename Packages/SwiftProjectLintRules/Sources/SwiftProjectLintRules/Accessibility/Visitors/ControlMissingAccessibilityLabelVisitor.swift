import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects an interactive control created with an **empty string label** and no
/// compensating `.accessibilityLabel`.
///
/// `Toggle("", isOn:).labelsHidden()` and `Button("", action:)` are visible and
/// tappable but expose no accessible name, so VoiceOver announces them as an
/// unlabeled checkbox/button. (This is exactly the gap the icon-only-button rule
/// doesn't cover, since here the label argument is present but empty.)
///
/// Not flagged:
/// - a non-empty label: `Toggle("Bold", isOn:)`
/// - an empty label with a compensating modifier: `Toggle("", isOn:).accessibilityLabel("Bold")`
/// - the closure-label form `Button(action:) { Image(...) }` (handled by the
///   Icon-Only Button Missing Label rule)
final class ControlMissingAccessibilityLabelVisitor: BasePatternVisitor {

    /// Controls whose first positional argument is their (accessible) title.
    private static let labeledControls: Set<String> = ["Toggle", "Button"]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
              Self.labeledControls.contains(callee.baseName.text),
              let firstArgument = node.arguments.first,
              firstArgument.label == nil,
              isEmptyStringLiteral(firstArgument.expression) else {
            return .visitChildren
        }

        // A compensating `.accessibilityLabel` on the control's modifier chain is fine.
        guard AccessibilityTreeTraverser.hasAccessibilityModifier(
            in: node, modifierName: "accessibilityLabel"
        ) == false else {
            return .visitChildren
        }

        addIssue(
            severity: .warning,
            message: "\(callee.baseName.text) has an empty label and no .accessibilityLabel "
                + "— it is unlabeled for VoiceOver",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Give the control a real label (e.g. "
                + "Toggle(name, isOn:).labelsHidden() keeps the layout while labelling it for "
                + "VoiceOver), or add .accessibilityLabel(\"…\").",
            ruleName: .controlMissingAccessibilityLabel
        )
        return .visitChildren
    }

    /// True for `""` and a literal made only of empty string segments (no interpolation).
    private func isEmptyStringLiteral(_ expression: ExprSyntax) -> Bool {
        guard let literal = expression.as(StringLiteralExprSyntax.self) else { return false }
        if literal.segments.isEmpty { return true }
        return literal.segments.allSatisfy { segment in
            guard let stringSegment = segment.as(StringSegmentSyntax.self) else { return false }
            return stringSegment.content.text.isEmpty
        }
    }
}

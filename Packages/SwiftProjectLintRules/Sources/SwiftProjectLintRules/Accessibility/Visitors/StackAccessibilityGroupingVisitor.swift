import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `VStack` and `HStack` views containing exactly two `Text` children
/// (and no interactive elements) that lack `.accessibilityElement(children:)`.
///
/// Without grouping, VoiceOver reads each `Text` as a separate element,
/// which can strip label–value context. For example, a stack with
/// "Temperature" and "72°F" would be read individually instead of together.
///
/// Flagged:
/// ```swift
/// VStack {
///     Text("Temperature")
///     Text("72°F")
/// }
/// // Missing .accessibilityElement(children: .combine)
/// ```
final class StackAccessibilityGroupingVisitor: BasePatternVisitor {

    /// Interactive view names — stacks containing these are excluded.
    private static let interactiveViews: Set<String> = [
        "Button", "Toggle", "Slider", "Stepper", "Picker",
        "DatePicker", "ColorPicker", "TextField", "SecureField",
        "TextEditor", "Link", "NavigationLink", "Menu"
    ]

    /// Stack view names to check.
    private static let stackViews: Set<String> = ["VStack", "HStack"]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isTestOrFixtureFile() { return .visitChildren }
        detectUngroupedStack(node)
        return .visitChildren
    }

    private func detectUngroupedStack(_ node: FunctionCallExprSyntax) {
        // Must be a VStack or HStack call
        guard let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
              Self.stackViews.contains(calledExpr.baseName.text) else { return }

        let stackName = calledExpr.baseName.text

        // Already has .accessibilityElement — nothing to flag
        if AccessibilityTreeTraverser.hasAccessibilityModifier(
            in: node, modifierName: "accessibilityElement"
        ) { return }

        // Already hidden from VoiceOver
        if AccessibilityTreeTraverser.hasAccessibilityModifier(
            in: node, modifierName: "accessibilityHidden"
        ) { return }

        // Get the trailing closure (the stack body)
        guard let body = node.trailingClosure else { return }

        // Count direct Text children and check for interactive elements
        var textCount = 0
        var hasInteractive = false

        for statement in body.statements {
            guard let item = topLevelCallName(Syntax(statement.item)) else { continue }

            if item == "Text" {
                textCount += 1
            } else if Self.interactiveViews.contains(item) {
                hasInteractive = true
                break
            }
        }

        // Flag stacks with exactly 2 Text children and nothing interactive
        guard textCount == 2, !hasInteractive else { return }

        addIssue(
            severity: .info,
            message: "\(stackName) with label–value Text pair may need "
                + ".accessibilityElement(children:) for VoiceOver grouping",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Add .accessibilityElement(children: .combine) so "
                + "VoiceOver reads the label and value together.",
            ruleName: .stackMissingAccessibilityGrouping
        )
    }

    /// Returns the top-level function call name from a code block item,
    /// walking through any modifier chains to find the root call.
    private func topLevelCallName(_ item: Syntax) -> String? {
        // Direct call: Text("hello")
        if let call = item.as(FunctionCallExprSyntax.self) {
            return rootCallName(call)
        }
        return nil
    }

    /// Walks through chained modifier calls to find the root view name.
    /// e.g., Text("hi").bold().padding() → "Text"
    private func rootCallName(_ call: FunctionCallExprSyntax) -> String? {
        if let ref = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        // Chained: .modifier(args) where base is another call
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let base = member.base?.as(FunctionCallExprSyntax.self) {
            return rootCallName(base)
        }
        return nil
    }
}

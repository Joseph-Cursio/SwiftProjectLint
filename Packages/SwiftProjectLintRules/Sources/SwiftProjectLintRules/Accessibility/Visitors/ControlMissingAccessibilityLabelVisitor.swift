import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects an interactive control whose label is **present but empty**, with no
/// compensating `.accessibilityLabel`.
///
/// `Toggle("", isOn:).labelsHidden()` and `Button("", action:)` are visible and
/// tappable but expose no accessible name, so VoiceOver announces them as an
/// unlabeled checkbox/button. (This is exactly the gap the icon-only-button rule
/// doesn't cover, since here the label argument is present but empty.)
///
/// Two shapes count as an empty label:
/// - an empty string title — `Toggle("", isOn:)`, `Picker("", selection:)`
/// - an empty label closure — `Toggle(isOn:) { }`, `Stepper(value:) { EmptyView() }`
///
/// `Picker` is deliberately excluded from the closure check: its trailing closure
/// is the *content* (the options), not the label, so an empty one there means
/// something else entirely.
///
/// Not flagged:
/// - a non-empty label: `Toggle("Bold", isOn:)`
/// - an empty label with a compensating modifier: `Toggle("", isOn:).accessibilityLabel("Bold")`
/// - a control whose label is *absent* rather than empty — `Slider(value:in:)` — which
///   is a different (and much more common) shape
/// - a control inside a group that merges or ignores its children, since the parent
///   then supplies the accessible name
/// - the closure-label form `Button(action:) { Image(...) }` (handled by the
///   Icon-Only Button Missing Label rule)
final class ControlMissingAccessibilityLabelVisitor: BasePatternVisitor {

    /// Controls whose first positional argument is their (accessible) title.
    private static let labeledControls: Set<String> = [
        "Toggle", "Button", "Slider", "Stepper", "Picker"
    ]

    /// Controls whose trailing closure is the label. `Picker`'s is the option
    /// content, so it is absent here on purpose.
    private static let closureLabelledControls: Set<String> = [
        "Toggle", "Slider", "Stepper"
    ]

    /// Parent groupings that take over naming, making an unlabeled child harmless:
    /// `.combine` merges the children's labels, `.ignore` removes them from the tree.
    private static let groupingChildBehaviours: Set<String> = ["combine", "ignore"]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
              Self.labeledControls.contains(callee.baseName.text),
              let emptiness = emptyLabelShape(of: node, control: callee.baseName.text) else {
            return .visitChildren
        }

        // A compensating `.accessibilityLabel` on the control's modifier chain is fine.
        guard AccessibilityTreeTraverser.hasAccessibilityModifier(
            in: node, modifierName: "accessibilityLabel"
        ) == false else {
            return .visitChildren
        }

        // A parent that merges or ignores its children names the group itself.
        guard isInsideNamingGroup(node) == false else { return .visitChildren }

        addIssue(
            severity: .warning,
            message: "\(callee.baseName.text) has \(emptiness) and no .accessibilityLabel "
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

    /// Describes how the control's label is empty, or nil when it is not.
    private func emptyLabelShape(of node: FunctionCallExprSyntax, control: String) -> String? {
        if let firstArgument = node.arguments.first,
           firstArgument.label == nil,
           isEmptyStringLiteral(firstArgument.expression) {
            return "an empty label"
        }

        guard Self.closureLabelledControls.contains(control) else { return nil }

        // `Toggle(isOn:) { }` — the trailing closure is the label, and it renders nothing.
        if let trailing = node.trailingClosure, isEmptyClosure(trailing) {
            return "an empty label closure"
        }
        // The explicit `label:` spelling.
        if let labelArgument = node.arguments.first(where: { $0.label?.text == "label" }),
           let closure = labelArgument.expression.as(ClosureExprSyntax.self),
           isEmptyClosure(closure) {
            return "an empty label closure"
        }
        return nil
    }

    /// True for `{ }` and for a closure whose only content is `EmptyView()`.
    private func isEmptyClosure(_ closure: ClosureExprSyntax) -> Bool {
        let statements = closure.statements
        if statements.isEmpty { return true }
        guard statements.count == 1,
              let call = statements.first?.item.as(FunctionCallExprSyntax.self),
              let callee = call.calledExpression.as(DeclReferenceExprSyntax.self) else {
            return false
        }
        return callee.baseName.text == "EmptyView" && call.arguments.isEmpty
    }

    /// True when any ancestor applies `.accessibilityElement(children: .combine/.ignore)`.
    ///
    /// A parent's modifier call is an ancestor of the control in the syntax tree, so one
    /// upward walk covers both the control's own chain and any enclosing container's —
    /// no separate parent tracking needed.
    private func isInsideNamingGroup(_ node: FunctionCallExprSyntax) -> Bool {
        var current: Syntax? = Syntax(node)

        while let syntax = current {
            if let call = syntax.as(FunctionCallExprSyntax.self),
               let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               member.declName.baseName.text == "accessibilityElement",
               groupsChildren(call.arguments) {
                return true
            }
            current = syntax.parent
        }
        return false
    }

    private func groupsChildren(_ arguments: LabeledExprListSyntax) -> Bool {
        arguments.contains { argument in
            guard argument.label?.text == "children",
                  let member = argument.expression.as(MemberAccessExprSyntax.self) else {
                return false
            }
            return Self.groupingChildBehaviours.contains(member.declName.baseName.text)
        }
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

import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a control written with **no label at all**, and no compensating
/// `.accessibilityLabel`.
///
/// `Slider(value: $volume, in: 0...1)` announces to VoiceOver as "50 percent,
/// slider" — a value and a role, with nothing saying *what* it adjusts. The user
/// can operate it perfectly well and still have no idea what it does.
///
/// This is the sibling of Control Missing Accessibility Label, which covers labels
/// that are present but *empty*. The split matters because the fixes differ: there
/// you blank out a label you already have, here you never wrote one.
///
/// **Scope is narrower than it first appears.** Most SwiftUI controls cannot be
/// written without a label — `Toggle`, `Stepper`, and `Picker` all require either a
/// string title or a label closure in every initializer, so they can only ever have
/// an *empty* label, never an absent one. Only `Slider` and `ProgressView` ship
/// label-less initializers, so only they can reach this rule.
///
/// Opt-in, because `Slider(value:in:)` is the ordinary way to write a slider and a
/// default-on rule would fire across most codebases at once.
///
/// Not flagged:
/// - a label closure, however spelled: `Slider(value:) { Text("Volume") }`
/// - a compensating `.accessibilityLabel` on the chain
/// - a control inside a group that merges or ignores its children
/// - the indeterminate `ProgressView()` spinner, which is usually decorative and
///   explained by adjacent text
final class UnlabeledControlVisitor: BasePatternVisitor {

    /// Controls with label-less initializers. Deliberately short: every other
    /// SwiftUI control requires a label, so it cannot reach this rule.
    private static let labelOptionalControls: Set<String> = ["Slider", "ProgressView"]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isTestOrFixtureFile() { return .visitChildren }

        guard let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
              Self.labelOptionalControls.contains(callee.baseName.text),
              carriesAValue(node),
              hasNoLabel(node) else {
            return .visitChildren
        }

        guard AccessibilityTreeTraverser.hasAccessibilityModifier(
            in: node, modifierName: "accessibilityLabel"
        ) == false else {
            return .visitChildren
        }

        guard AccessibilityTreeTraverser.isInsideNamingGroup(node) == false else {
            return .visitChildren
        }

        addIssue(
            severity: .warning,
            message: "\(callee.baseName.text) has no label — VoiceOver announces its value "
                + "and role but not what it controls",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Add a label closure, e.g. Slider(value: $volume, in: 0...1) "
                + "{ Text(\"Volume\") }, or add .accessibilityLabel(\"Volume\").",
            ruleName: .unlabeledControl
        )
        return .visitChildren
    }

    /// True when the control reports a value worth naming. A bare `ProgressView()`
    /// spinner is excluded: it is usually decorative and explained by nearby text.
    private func carriesAValue(_ node: FunctionCallExprSyntax) -> Bool {
        node.arguments.contains { $0.label?.text == "value" }
    }

    /// True when no label is supplied in any spelling — no string title, no trailing
    /// closure, no explicit `label:`.
    private func hasNoLabel(_ node: FunctionCallExprSyntax) -> Bool {
        if node.trailingClosure != nil { return false }
        if node.arguments.contains(where: { $0.label?.text == "label" }) { return false }
        // A leading positional argument is the control's title.
        if let first = node.arguments.first, first.label == nil { return false }
        return true
    }
}

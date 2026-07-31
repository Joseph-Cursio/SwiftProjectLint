import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a view that declares itself a button to assistive technology via
/// `.accessibilityAddTraits(.isButton)` but offers no way to activate it.
///
/// VoiceOver announces the element as a button and offers the activate gesture,
/// but the double-tap reaches nothing. The trait is a promise about behaviour,
/// and this is that promise unkept.
///
/// Flagged:
/// ```swift
/// HStack {
///     Text("Mars")
///     Image(systemName: "heart")
/// }
/// .accessibilityElement(children: .ignore)
/// .accessibilityAddTraits(.isButton)
/// ```
///
/// Not flagged:
/// - the chain supplies an activation path — `.accessibilityAction`, a custom
///   action, or a tap/long-press gesture
/// - the view is already activatable (`Button`, `NavigationLink`, `Link`, …),
///   where the trait is redundant rather than broken
///
/// Known limitation: activation inherited from an ancestor view or an enclosing
/// gesture is not visible from this chain, so such cases report a false positive.
final class IsButtonTraitWithoutActionVisitor: BasePatternVisitor {

    /// Modifiers that give the element something for the activate gesture to reach.
    private static let activationModifiers: Set<String> = [
        "accessibilityAction",
        "accessibilityCustomAction",
        "accessibilityAdjustableAction",
        "onTapGesture",
        "onLongPressGesture",
        "gesture",
        "highPriorityGesture",
        "simultaneousGesture"
    ]

    /// Views that already carry an action, where `.isButton` is merely redundant.
    private static let activatableViews: Set<String> = [
        "Button", "NavigationLink", "Link", "Menu", "Toggle", "Stepper", "Picker"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isTestOrFixtureFile() { return .visitChildren }
        detectUnactionableButtonTrait(node)
        return .visitChildren
    }

    private func detectUnactionableButtonTrait(_ node: FunctionCallExprSyntax) {
        // Anchor on the root view call rather than a modifier call, so the whole
        // chain is examined once and the modifiers' order does not matter.
        if node.calledExpression.is(MemberAccessExprSyntax.self) { return }

        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
           Self.activatableViews.contains(callee.baseName.text) {
            return
        }

        let modifiers = collectModifiers(from: node)

        guard let traitCall = modifiers.first(where: {
            $0.name == "accessibilityAddTraits" && addsIsButtonTrait($0.call)
        }) else { return }

        guard modifiers.contains(where: { Self.activationModifiers.contains($0.name) }) == false else {
            return
        }

        addIssue(
            severity: .warning,
            message: ".accessibilityAddTraits(.isButton) announces this as a button, but nothing "
                + "handles the activate gesture — VoiceOver users cannot trigger it",
            filePath: getFilePath(for: Syntax(traitCall.call)),
            lineNumber: getLineNumber(for: Syntax(traitCall.call)),
            suggestion: "Add .accessibilityAction { … } to handle activation, or make the view a "
                + "Button, which carries the trait and the action together.",
            ruleName: .isButtonTraitWithoutAction
        )
    }

    /// True when the call adds `.isButton`, either bare or inside a trait array.
    private func addsIsButtonTrait(_ call: FunctionCallExprSyntax) -> Bool {
        call.arguments.contains { argument in
            if isButtonTrait(argument.expression) { return true }
            guard let array = argument.expression.as(ArrayExprSyntax.self) else { return false }
            return array.elements.contains { isButtonTrait($0.expression) }
        }
    }

    private func isButtonTrait(_ expression: ExprSyntax) -> Bool {
        expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "isButton"
    }

    /// Walks up the modifier chain, pairing each modifier name with its call.
    private func collectModifiers(
        from node: FunctionCallExprSyntax
    ) -> [(name: String, call: FunctionCallExprSyntax)] {
        var modifiers: [(name: String, call: FunctionCallExprSyntax)] = []
        var current = Syntax(node)

        while let memberAccess = current.parent?.as(MemberAccessExprSyntax.self),
              let modifierCall = memberAccess.parent?.as(FunctionCallExprSyntax.self) {
            modifiers.append((memberAccess.declName.baseName.text, modifierCall))
            current = Syntax(modifierCall)
        }
        return modifiers
    }
}

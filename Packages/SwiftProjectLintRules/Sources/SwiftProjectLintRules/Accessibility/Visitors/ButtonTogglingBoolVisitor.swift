import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `Button` views whose action closure calls `.toggle()` on a variable,
/// suggesting the button is being used as a toggle control. A `Toggle` with a
/// custom `ToggleStyle` preserves semantic accessibility traits automatically.
///
/// Flagged:
/// ```swift
/// Button {
///     isEnabled.toggle()
/// } label: {
///     Text(isEnabled ? "On" : "Off")
/// }
/// ```
final class ButtonTogglingBoolVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isTestOrFixtureFile() { return .visitChildren }
        detectButtonToggle(node)
        return .visitChildren
    }

    private func detectButtonToggle(_ node: FunctionCallExprSyntax) {
        // Must be a Button call
        guard let calledExpr = node.calledExpression.as(DeclReferenceExprSyntax.self),
              calledExpr.baseName.text == "Button" else { return }

        // Look for .toggle() in the action closure.
        // Button("Title") { action } — action is the trailing closure when
        //   there is no explicit `label:` argument, but only when the Button
        //   has a string-title init. For the closure-based init
        //   Button(action:label:), the action is the first argument closure
        //   and label is the trailing closure.

        // Check first positional closure argument (action: { ... })
        for argument in node.arguments {
            if let closure = argument.expression.as(ClosureExprSyntax.self),
               containsToggleCall(in: closure) {
                reportIssue(node)
                return
            }
        }

        // Check trailing closure — for Button("Title") { action } form
        if let trailing = node.trailingClosure,
           containsToggleCall(in: trailing) {
            // Only flag if there's no separate label: argument (otherwise the
            // trailing closure is the label, not the action)
            let hasLabelArg = node.arguments.contains { $0.label?.text == "label" }
            if !hasLabelArg {
                reportIssue(node)
                return
            }
        }
    }

    private func reportIssue(_ node: FunctionCallExprSyntax) {
        addIssue(
            severity: .info,
            message: "Button that toggles a Bool could be a Toggle "
                + "with a custom ToggleStyle",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use Toggle(\"Label\", isOn: $value) with a custom "
                + "ToggleStyle to get semantic accessibility traits automatically.",
            ruleName: .buttonTogglingBool
        )
    }

    /// Checks whether a closure contains a `.toggle()` call.
    private func containsToggleCall(in closure: ClosureExprSyntax) -> Bool {
        for statement in closure.statements
            where hasToggleCall(in: Syntax(statement)) {
            return true
        }
        return false
    }

    /// Recursively checks for a `.toggle()` member function call.
    private func hasToggleCall(in syntax: Syntax) -> Bool {
        if let call = syntax.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "toggle",
           call.arguments.isEmpty {
            return true
        }
        for child in syntax.children(viewMode: .sourceAccurate)
            where hasToggleCall(in: child) {
            return true
        }
        return false
    }
}

import SwiftSyntax

/// A SwiftSyntax visitor that detects the use of the deprecated `.animation()` modifier in SwiftUI.
class AnimationVisitor: BasePatternVisitor {

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // We are looking for `.animation(...)`
        guard let calledExpression = node.calledExpression.as(MemberAccessExprSyntax.self),
              calledExpression.declName.baseName.text == "animation" else {
            return .visitChildren
        }

        // The deprecated version lacks a `value` parameter.
        let hasValueArgument = node.arguments.contains { $0.label?.text == "value" }

        if !hasValueArgument {
            let animationType = node.arguments.first?.expression.description ?? ".default"
            addIssue(
                severity: .warning,
                message: "Use of the deprecated `.animation()` modifier should be avoided.",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Replace `.animation(\(animationType))` with `.animation(\(animationType), value: yourStateVariable)` to ensure animations only trigger when a specific state changes.",
                ruleName: .deprecatedAnimation
            )
        }

        return .visitChildren
    }
}

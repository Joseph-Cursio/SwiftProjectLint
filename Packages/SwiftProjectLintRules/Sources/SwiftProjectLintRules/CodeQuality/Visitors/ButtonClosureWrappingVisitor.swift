import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `Button("Label") { singleCall() }` patterns.
///
/// When a Button's trailing closure contains only a single no-argument function call,
/// the closure can be replaced with the `action:` parameter for cleaner code.
final class ButtonClosureWrappingVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        detectButtonClosureWrapping(node)
        return .visitChildren
    }

    private func detectButtonClosureWrapping(_ node: FunctionCallExprSyntax) {
        // Must be a Button call
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "Button" else { return }

        // Must have a trailing closure and no additional trailing closures
        // (excludes Button { action } label: { ... } form)
        guard let closure = node.trailingClosure,
              node.additionalTrailingClosures.isEmpty else { return }

        // Closure must have exactly one statement
        let statements = Array(closure.statements)
        guard statements.count == 1 else { return }

        // The single statement must be a function call with no arguments
        guard let innerCall = statements[0].item.as(FunctionCallExprSyntax.self),
              innerCall.arguments.isEmpty,
              innerCall.trailingClosure == nil else { return }

        // The called expression must be a simple identifier (not a member access)
        guard let innerRef = innerCall.calledExpression.as(DeclReferenceExprSyntax.self) else { return }

        let funcName = innerRef.baseName.text
        addIssue(
            severity: .info,
            message: "Button trailing closure wraps a single call to '\(funcName)()' — "
                + "use the action parameter instead",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use Button(\"...\", action: \(funcName)) for cleaner code.",
            ruleName: .buttonClosureWrapping
        )
    }
}

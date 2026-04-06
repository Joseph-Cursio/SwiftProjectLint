import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects Task { } inside .onAppear { } closures that should use the .task { } modifier.
final class TaskInOnAppearVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        detectTaskInOnAppear(node)
        return .visitChildren
    }

    private func detectTaskInOnAppear(_ node: FunctionCallExprSyntax) {
        guard isTaskCall(node), isInsideOnAppearClosure(Syntax(node)) else { return }

        addIssue(
            severity: .warning,
            message: "Task created inside .onAppear — lifecycle is not tied to the view",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use the .task { } view modifier instead — it cancels automatically "
                + "when the view disappears.",
            ruleName: .taskInOnAppear
        )
    }

    private func isTaskCall(_ node: FunctionCallExprSyntax) -> Bool {
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
           declRef.baseName.text == "Task" {
            return true
        }
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "detached",
           let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "Task" {
            return true
        }
        return false
    }

    private func isInsideOnAppearClosure(_ syntax: Syntax) -> Bool {
        var current = syntax
        while let parent = current.parent {
            // Stop at function declaration boundaries
            if parent.is(FunctionDeclSyntax.self) { return false }

            // Check if we're crossing a closure boundary
            if current.is(ClosureExprSyntax.self) {
                // Check if this closure is the trailing closure of .onAppear
                if let callExpr = parent.as(FunctionCallExprSyntax.self),
                   let memberAccess = callExpr.calledExpression.as(MemberAccessExprSyntax.self),
                   memberAccess.declName.baseName.text == "onAppear" {
                    return true
                }
                // Also check if closure is inside a labeled argument of .onAppear
                if let labeledExpr = parent.as(LabeledExprSyntax.self),
                   let argList = labeledExpr.parent,
                   let callExpr = argList.parent?.as(FunctionCallExprSyntax.self),
                   let memberAccess = callExpr.calledExpression.as(MemberAccessExprSyntax.self),
                   memberAccess.declName.baseName.text == "onAppear" {
                    return true
                }
            }
            current = parent
        }
        return false
    }
}

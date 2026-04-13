import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects async functions that spawn tasks
/// without checking for cancellation.
///
/// An async function that creates `Task { }`, `withTaskGroup`, or
/// `withThrowingTaskGroup` but never checks `Task.isCancelled` or calls
/// `Task.checkCancellation()` may perform unnecessary work after the parent
/// task has been cancelled.
final class MissingCancellationCheckVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.signature.effectSpecifiers?.asyncSpecifier != nil,
              let body = node.body else {
            return .visitChildren
        }

        let bodySyntax = Syntax(body)

        guard containsTaskCreation(in: bodySyntax) else { return .visitChildren }
        guard !containsCancellationCheck(in: bodySyntax) else { return .visitChildren }

        addIssue(
            severity: .warning,
            message: "Async function '\(node.name.text)' spawns tasks without checking cancellation",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Add 'guard !Task.isCancelled else { return }' or "
                + "'try Task.checkCancellation()' to avoid unnecessary work after cancellation.",
            ruleName: .missingCancellationCheck
        )

        return .visitChildren
    }

    // MARK: - Task Creation Detection

    private func containsTaskCreation(in syntax: Syntax) -> Bool {
        containsNode(in: syntax, matching: isTaskCreation)
    }

    private func isTaskCreation(_ syntax: Syntax) -> Bool {
        guard let call = syntax.as(FunctionCallExprSyntax.self) else { return false }

        // Task { }
        if let declRef = call.calledExpression.as(DeclReferenceExprSyntax.self),
           declRef.baseName.text == "Task" {
            return true
        }

        // withTaskGroup / withThrowingTaskGroup
        if let declRef = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = declRef.baseName.text
            if name == "withTaskGroup" || name == "withThrowingTaskGroup" {
                return true
            }
        }

        return false
    }

    // MARK: - Cancellation Check Detection

    private func containsCancellationCheck(in syntax: Syntax) -> Bool {
        containsNode(in: syntax, matching: isCancellationCheck)
    }

    private func isCancellationCheck(_ syntax: Syntax) -> Bool {
        // Task.isCancelled  (property access, not a call)
        if let member = syntax.as(MemberAccessExprSyntax.self),
           let base = member.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "Task",
           member.declName.baseName.text == "isCancelled" {
            return true
        }

        // Task.checkCancellation()
        if let call = syntax.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           let base = member.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "Task",
           member.declName.baseName.text == "checkCancellation" {
            return true
        }

        return false
    }

    // MARK: - Generic Tree Walk

    /// Walks the syntax tree looking for a node that satisfies `predicate`.
    /// Does not descend into nested function declarations (separate scope).
    private func containsNode(in syntax: Syntax, matching predicate: (Syntax) -> Bool) -> Bool {
        if predicate(syntax) { return true }
        // Stop at nested function declarations — they are a separate scope
        if syntax.is(FunctionDeclSyntax.self) { return false }
        return syntax.children(viewMode: .sourceAccurate)
            .contains { containsNode(in: $0, matching: predicate) }
    }
}

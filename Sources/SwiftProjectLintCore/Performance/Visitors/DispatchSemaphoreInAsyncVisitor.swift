import SwiftSyntax

/// Detects DispatchSemaphore usage inside async functions.
final class DispatchSemaphoreInAsyncVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .dispatchSemaphoreInAsync else { return .visitChildren }
        detectSemaphoreInAsync(node)
        return .visitChildren
    }

    private func detectSemaphoreInAsync(_ node: FunctionCallExprSyntax) {
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "DispatchSemaphore" else { return }

        guard isInsideAsyncContext(Syntax(node)) else { return }

        addIssue(
            severity: .warning,
            message: "DispatchSemaphore used inside an async context — "
                + ".wait() blocks the cooperative thread pool",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use Swift Concurrency primitives (AsyncStream, continuation, "
                + "or actor isolation) instead of semaphores in async code.",
            ruleName: .dispatchSemaphoreInAsync
        )
    }

    private func isInsideAsyncContext(_ syntax: Syntax) -> Bool {
        var current = syntax
        while let parent = current.parent {
            if let funcDecl = parent.as(FunctionDeclSyntax.self) {
                return funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
            }
            // Stop at closure boundaries — check if the closure itself is async
            if let closure = parent.as(ClosureExprSyntax.self) {
                if let signature = closure.signature,
                   let effectSpecifiers = signature.effectSpecifiers,
                   effectSpecifiers.asyncSpecifier != nil {
                    return true
                }
                // Non-async closure is a sync boundary — semaphore is fine here
                return false
            }
            current = parent
        }
        return false
    }
}

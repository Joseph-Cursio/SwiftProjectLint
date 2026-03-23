import SwiftSyntax

/// A SwiftSyntax visitor that detects `Task { try ... }` without `do/catch`.
///
/// Errors thrown inside a Task closure that lacks a do/catch block are silently
/// lost. The caller never sees the failure unless it inspects `Task.result`.
final class SwallowedTaskErrorVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .swallowedTaskError else { return .visitChildren }

        // Must be Task { } (not Task.detached)
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "Task",
              let closure = node.trailingClosure else { return .visitChildren }

        // Check for bare `try` (not `try?` or `try!`) — only bare try loses errors
        let hasBareTry = containsBareTry(in: closure.statements)
        let hasDoCatch = containsNodeInStatements(
            ofType: DoStmtSyntax.self, in: closure.statements
        )

        if hasBareTry && !hasDoCatch && !isTaskResultConsumed(node) {
            addIssue(
                severity: .warning,
                message: "Task closure uses 'try' without do/catch "
                    + "— errors are silently lost",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Wrap throwing code in do/catch inside the Task, "
                    + "or handle the error via Task.result.",
                ruleName: .swallowedTaskError
            )
        }
        return .visitChildren
    }

    // MARK: - Task Result Consumption

    /// Returns `true` when the Task's result is consumed (errors propagate to the caller).
    ///
    /// Matches patterns like:
    /// - `try await Task { ... }.value`
    /// - `Task { ... }.result`
    /// - `let task = Task { ... }` (stored for later `.value`/`.result` access)
    private func isTaskResultConsumed(_ node: FunctionCallExprSyntax) -> Bool {
        guard let parent = node.parent else { return false }

        // Pattern 1: Task { ... }.value  or  Task { ... }.result
        // The parent of the FunctionCallExpr is a MemberAccessExpr
        if let memberAccess = parent.as(MemberAccessExprSyntax.self) {
            let member = memberAccess.declName.baseName.text
            if member == "value" || member == "result" {
                return true
            }
        }

        // Pattern 2: let task = Task { ... }  (assigned to a variable)
        if parent.is(InitializerClauseSyntax.self) {
            return true
        }

        // Pattern 3: try await Task { ... }.value — the FunctionCallExpr may be
        // wrapped in an AwaitExprSyntax or TryExprSyntax before the MemberAccess.
        // Walk up through Await/Try wrappers to find a MemberAccess.
        var current: Syntax? = parent
        while let ancestor = current {
            if let memberAccess = ancestor.as(MemberAccessExprSyntax.self) {
                let member = memberAccess.declName.baseName.text
                if member == "value" || member == "result" {
                    return true
                }
            }
            // Stop at statement boundaries
            if ancestor.is(CodeBlockItemSyntax.self) { break }
            current = ancestor.parent
        }

        return false
    }

    // MARK: - Recursive Node Search

    /// Checks if the statements contain a bare `try` (not `try?` or `try!`).
    private func containsBareTry(in statements: CodeBlockItemListSyntax) -> Bool {
        statements.contains { containsBareTryNode(in: Syntax($0)) }
    }

    private func containsBareTryNode(in syntax: Syntax) -> Bool {
        if let tryExpr = syntax.as(TryExprSyntax.self) {
            // Only bare `try` — questionOrExclamationMark is nil
            if tryExpr.questionOrExclamationMark == nil { return true }
        }
        if syntax.is(FunctionDeclSyntax.self) { return false }
        if syntax.is(ClosureExprSyntax.self) { return false }
        return syntax.children(viewMode: .sourceAccurate)
            .contains { containsBareTryNode(in: $0) }
    }

    private func containsNodeInStatements<T: SyntaxProtocol>(
        ofType type: T.Type,
        in statements: CodeBlockItemListSyntax
    ) -> Bool {
        statements.contains { containsNode(ofType: type, in: Syntax($0)) }
    }

    private func containsNode<T: SyntaxProtocol>(
        ofType type: T.Type,
        in syntax: Syntax
    ) -> Bool {
        if syntax.is(type) { return true }
        // Don't descend into nested functions or closures
        if syntax.is(FunctionDeclSyntax.self) { return false }
        if syntax.is(ClosureExprSyntax.self) { return false }
        return syntax.children(viewMode: .sourceAccurate)
            .contains { containsNode(ofType: type, in: $0) }
    }
}

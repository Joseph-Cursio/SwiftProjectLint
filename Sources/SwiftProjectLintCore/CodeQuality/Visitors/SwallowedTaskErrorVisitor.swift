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

        let hasTry = containsNodeInStatements(
            ofType: TryExprSyntax.self, in: closure.statements
        )
        let hasDoCatch = containsNodeInStatements(
            ofType: DoStmtSyntax.self, in: closure.statements
        )

        if hasTry && !hasDoCatch {
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

    // MARK: - Recursive Node Search

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

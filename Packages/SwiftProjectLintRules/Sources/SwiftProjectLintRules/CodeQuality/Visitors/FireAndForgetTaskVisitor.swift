import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects fire-and-forget `Task { }` calls.
///
/// A "fire-and-forget" `Task` is one where the handle is immediately discarded —
/// the call is an expression statement and the result is never stored or awaited.
/// This pattern is common in AI-generated code and causes subtle bugs:
/// - Thrown errors are silently lost if no `do/catch` wraps the body.
/// - There is no handle to cancel, observe, or await the task.
/// - The task may outlive the object that spawned it, causing use-after-free bugs.
///
/// Suppress with the standard inline directive when intentional:
/// ```swift
/// // swiftprojectlint:disable:next fire-and-forget-task
/// Task { await logMetrics() }
/// ```
///
/// `Task.detached` is intentionally excluded; it is already flagged by `TaskDetachedVisitor`.
final class FireAndForgetTaskVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Plain `Task { }` only — not `Task.detached` (covered by TaskDetachedVisitor)
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "Task",
              node.trailingClosure != nil else {
            return .visitChildren
        }

        guard !isResultConsumed(node) else { return .visitChildren }

        addIssue(
            severity: .warning,
            message: "Fire-and-forget Task — the handle is discarded and the task "
                + "cannot be cancelled or observed",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Store the Task handle ('let task = Task { }') so it can be "
                + "cancelled and awaited. If intentional, suppress with "
                + "'// swiftprojectlint:disable:next fire-and-forget-task'.",
            ruleName: .fireAndForgetTask
        )

        return .visitChildren
    }

    // MARK: - Result Consumption

    /// Returns `true` when the Task handle is captured rather than immediately discarded.
    ///
    /// Matches:
    /// - `let task = Task { ... }` — stored for later use
    /// - `try await Task { ... }.value` — errors propagate to the caller
    /// - `Task { ... }.result` — result captured by the caller
    private func isResultConsumed(_ node: FunctionCallExprSyntax) -> Bool {
        guard let parent = node.parent else { return false }

        // Pattern: let task = Task { ... }
        if parent.is(InitializerClauseSyntax.self) { return true }

        // Pattern: Task { ... }.value  /  Task { ... }.result
        if let member = parent.as(MemberAccessExprSyntax.self) {
            let name = member.declName.baseName.text
            if name == "value" || name == "result" { return true }
        }

        // Walk up through Await/Try wrappers to find a MemberAccess (.value / .result)
        var current: Syntax? = parent
        while let ancestor = current {
            if let member = ancestor.as(MemberAccessExprSyntax.self) {
                let name = member.declName.baseName.text
                if name == "value" || name == "result" { return true }
            }
            if ancestor.is(CodeBlockItemSyntax.self) { break }
            current = ancestor.parent
        }

        return false
    }
}

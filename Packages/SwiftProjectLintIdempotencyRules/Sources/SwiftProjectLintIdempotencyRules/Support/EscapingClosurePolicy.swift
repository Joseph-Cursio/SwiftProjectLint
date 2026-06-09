import SwiftSyntax

/// Shared closure-escaping policy for the idempotency visitors.
///
/// A trailing closure is treated as *escaping* — a replay boundary that the
/// Phase 1 body checks stop at — when its nearest enclosing call targets one
/// of ``calleeNames`` (the structured-concurrency and SwiftUI task
/// primitives). See `IdempotencyViolationVisitor` for the full rationale.
enum EscapingClosurePolicy {

    /// Callees whose trailing closures are treated as escaping for Phase 1
    /// purposes. `task` is deliberately included so that SwiftUI's
    /// `.task { … }` modifier boundary is honoured — the runtime re-runs the
    /// closure on view identity changes, so it's a genuine replay boundary,
    /// not part of the caller's synchronous body.
    static let calleeNames: Set<String> = [
        "Task",
        "detached",
        "withTaskGroup",
        "withThrowingTaskGroup",
        "withDiscardingTaskGroup",
        "withThrowingDiscardingTaskGroup",
        "task"
    ]

    /// A closure is escaping when its *nearest* enclosing `FunctionCallExprSyntax`
    /// targets a callee in ``calleeNames``. A closure deeply nested inside a
    /// non-escaping call is treated as non-escaping relative to the Phase 1
    /// body check — the scope stops at these boundaries.
    static func isEscaping(_ closure: ClosureExprSyntax) -> Bool {
        var node = Syntax(closure).parent
        while let current = node {
            if let call = current.as(FunctionCallExprSyntax.self) {
                if let name = directCalleeName(from: call.calledExpression),
                   calleeNames.contains(name) {
                    return true
                }
                return false
            }
            node = current.parent
        }
        return false
    }

    /// The bare callee name of a call's `calledExpression`, resolving either a
    /// direct reference (`foo()`) or a member access (`x.foo()`).
    static func directCalleeName(from expr: ExprSyntax) -> String? {
        if let ref = expr.as(DeclReferenceExprSyntax.self) {
            return ref.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }
}

import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `Task.detached { }` calls.
///
/// `Task.detached` breaks structured concurrency by creating an unstructured task
/// that does not inherit the current actor context or task-local values.
/// In most cases, a plain `Task { }` is the correct choice.
final class TaskDetachedVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .taskDetached else { return .visitChildren }

        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "detached",
              let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
              base.baseName.text == "Task" else {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: "Task.detached breaks structured concurrency",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use Task { } instead unless you specifically need to escape "
                + "the current actor context.",
            ruleName: .taskDetached
        )
        return .visitChildren
    }
}

import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `Task.yield()` calls.
///
/// `Task.yield()` gives up the executor momentarily but does not offload work.
/// If the following code is CPU-intensive, it should use `@concurrent` or
/// `Task.detached` instead.
final class TaskYieldOffloadVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .taskYieldOffload else { return .visitChildren }

        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "yield",
              let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
              base.baseName.text == "Task",
              node.arguments.isEmpty else { return .visitChildren }

        addIssue(
            severity: .info,
            message: "Task.yield() gives up the executor momentarily "
                + "but does not offload work",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "If the following work is CPU-intensive, use @concurrent "
                + "or Task.detached to offload it from the current actor.",
            ruleName: .taskYieldOffload
        )
        return .visitChildren
    }
}

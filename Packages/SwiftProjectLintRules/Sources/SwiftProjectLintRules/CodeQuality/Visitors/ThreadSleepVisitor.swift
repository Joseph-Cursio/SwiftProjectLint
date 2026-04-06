import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `Thread.sleep(forTimeInterval:)` calls.
///
/// `Thread.sleep` blocks the current thread entirely. In async contexts,
/// `Task.sleep(for:)` suspends cooperatively without blocking.
final class ThreadSleepVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        detectThreadSleep(node)
        return .visitChildren
    }

    private func detectThreadSleep(_ node: FunctionCallExprSyntax) {
        // Match Thread.sleep(...) — MemberAccessExpr "sleep" on DeclReferenceExpr "Thread"
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "sleep" else { return }

        guard let declRef = memberAccess.base?.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "Thread" else { return }

        addIssue(
            severity: .warning,
            message: "Thread.sleep blocks the current thread",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use try await Task.sleep(for:) to suspend cooperatively.",
            ruleName: .threadSleep
        )
    }
}

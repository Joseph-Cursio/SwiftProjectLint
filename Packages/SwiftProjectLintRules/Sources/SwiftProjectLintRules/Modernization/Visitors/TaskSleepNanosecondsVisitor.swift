import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `Task.sleep(nanoseconds:)` calls.
///
/// `Task.sleep(nanoseconds:)` was the original async sleep API but requires
/// manual nanosecond conversion. `Task.sleep(for:)` using `Duration` is the
/// modern replacement and is far more readable.
final class TaskSleepNanosecondsVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        detectTaskSleepNanoseconds(node)
        return .visitChildren
    }

    private func detectTaskSleepNanoseconds(_ node: FunctionCallExprSyntax) {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "sleep" else { return }

        guard let declRef = memberAccess.base?.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "Task" else { return }

        let hasNanosecondsLabel = node.arguments.contains { $0.label?.text == "nanoseconds" }
        guard hasNanosecondsLabel else { return }

        addIssue(
            severity: .warning,
            message: "Task.sleep(nanoseconds:) requires manual unit conversion",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use try await Task.sleep(for: .seconds(1)) or .milliseconds() with a Duration value.",
            ruleName: .taskSleepNanoseconds
        )
    }
}

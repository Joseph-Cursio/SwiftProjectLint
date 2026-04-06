import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `try!` expressions.
///
/// Force try will crash at runtime if the expression throws an error.
/// Using `try/catch` or `try?` provides safer error handling.
final class ForceTryVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        detectForceTry(node)
        return .visitChildren
    }

    private func detectForceTry(_ node: TryExprSyntax) {
        guard let mark = node.questionOrExclamationMark,
              mark.text == "!" else { return }

        addIssue(
            severity: .warning,
            message: "Force try (try!) will crash on error — use try/catch or try? instead",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use do/catch for error handling or try? to return nil on failure.",
            ruleName: .forceTry
        )
    }
}

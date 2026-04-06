import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `print()` and `debugPrint()` calls.
///
/// Print statements should be replaced with structured logging (e.g., `os.Logger`)
/// or removed before release builds.
final class PrintStatementVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        detectPrintCall(node)
        return .visitChildren
    }

    private func detectPrintCall(_ node: FunctionCallExprSyntax) {
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "print" || declRef.baseName.text == "debugPrint" else { return }

        addIssue(
            severity: .info,
            message: "print() statement found — consider using os.Logger or removing before release",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use os.Logger for structured logging or remove print statements before release.",
            ruleName: .printStatement
        )
    }
}

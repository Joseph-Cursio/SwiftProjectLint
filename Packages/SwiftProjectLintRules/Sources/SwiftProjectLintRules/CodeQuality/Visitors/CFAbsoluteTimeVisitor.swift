import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `CFAbsoluteTimeGetCurrent()` calls.
///
/// `CFAbsoluteTimeGetCurrent()` is a legacy Core Foundation API. For timing measurements,
/// `ContinuousClock` is preferred; for timestamps, `Date.now` is clearer.
final class CFAbsoluteTimeVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        detectCFAbsoluteTime(node)
        return .visitChildren
    }

    private func detectCFAbsoluteTime(_ node: FunctionCallExprSyntax) {
        // Match CFAbsoluteTimeGetCurrent() — DeclReferenceExpr with no arguments
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "CFAbsoluteTimeGetCurrent",
              node.arguments.isEmpty else { return }

        addIssue(
            severity: .info,
            message: "CFAbsoluteTimeGetCurrent() is a legacy Core Foundation API",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use ContinuousClock for timing measurements or Date.now for timestamps.",
            ruleName: .cfAbsoluteTime
        )
    }
}

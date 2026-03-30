import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `Date()` calls that should use `Date.now` instead.
///
/// `Date.now` (available since iOS 15 / macOS 12) is shorter, clearer, and avoids
/// an unnecessary initializer call.
final class DateNowVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .dateNow else { return .visitChildren }
        detectDateInit(node)
        return .visitChildren
    }

    private func detectDateInit(_ node: FunctionCallExprSyntax) {
        // Match Date() — DeclReferenceExpr "Date" with no arguments
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "Date",
              node.arguments.isEmpty else { return }

        addIssue(
            severity: .info,
            message: "Use Date.now instead of Date()",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Replace Date() with .now for clarity.",
            ruleName: .dateNow
        )
    }
}

import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `.fontWeight(.bold)` calls that can be replaced with `.bold()`.
final class FontWeightBoldVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "fontWeight",
              node.arguments.count == 1,
              let argExpr = node.arguments.first?.expression
                  .as(MemberAccessExprSyntax.self),
              argExpr.declName.baseName.text == "bold" else {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: ".fontWeight(.bold) can be simplified to .bold()",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Replace .fontWeight(.bold) with .bold()",
            ruleName: .fontWeightBold
        )
        return .visitChildren
    }
}

import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `ScrollView(..., showsIndicators: ...)` usage that should use the
/// `.scrollIndicators(.hidden)` modifier instead (iOS 16+).
final class ScrollViewShowsIndicatorsVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "ScrollView",
              node.arguments.contains(where: { $0.label?.text == "showsIndicators" }) else {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: "ScrollView(showsIndicators:) is the legacy scroll indicator API",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use .scrollIndicators(.hidden) modifier instead "
                + "(requires iOS 16+).",
            ruleName: .scrollViewShowsIndicators
        )
        return .visitChildren
    }
}

import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects deprecated `.foregroundColor()` modifier usage.
///
/// `.foregroundColor()` was deprecated in iOS 17. The replacement `.foregroundStyle()`
/// accepts `ShapeStyle` instead of just `Color`, enabling gradients, materials, and
/// hierarchical styles in addition to flat colors.
final class ForegroundColorDeprecatedVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "foregroundColor" else { return .visitChildren }

        addIssue(
            severity: .warning,
            message: ".foregroundColor() is deprecated in iOS 17",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use .foregroundStyle() instead — it accepts any ShapeStyle including gradients and materials.",
            ruleName: .foregroundColorDeprecated
        )
        return .visitChildren
    }
}

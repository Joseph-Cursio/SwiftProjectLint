import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects deprecated `NavigationView` usage.
///
/// `NavigationView` was deprecated in iOS 16 in favor of `NavigationStack`
/// (single-column) and `NavigationSplitView` (multi-column).
final class NavigationViewDeprecatedVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "NavigationView" else { return .visitChildren }

        addIssue(
            severity: .warning,
            message: "NavigationView is deprecated — use NavigationStack or NavigationSplitView",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Replace NavigationView with NavigationStack (single column) "
                + "or NavigationSplitView (multi-column) for iOS 16+.",
            ruleName: .navigationViewDeprecated
        )
        return .visitChildren
    }
}

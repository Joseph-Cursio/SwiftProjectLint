import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `AnyView` usage.
///
/// `AnyView` is a type-erased wrapper that hides the concrete view type from SwiftUI's
/// diffing engine. Because SwiftUI cannot see through the erasure, it must destroy and
/// recreate the wrapped view on every update instead of performing a targeted diff.
/// The fix is almost always `@ViewBuilder` or a generic constraint, both of which
/// preserve structural identity at zero runtime cost.
final class AnyViewUsageVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "AnyView" else { return .visitChildren }

        addIssue(
            severity: .warning,
            message: "AnyView erases the view type and prevents SwiftUI from diffing efficiently",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use @ViewBuilder or a generic constraint instead. "
                + "AnyView forces SwiftUI to destroy and recreate the wrapped view on every update.",
            ruleName: .anyViewUsage
        )
        return .visitChildren
    }
}

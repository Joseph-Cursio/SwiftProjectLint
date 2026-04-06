import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `ScrollViewReader` usage.
///
/// `ScrollViewReader` and `ScrollViewProxy.scrollTo(_:anchor:)` were the only way
/// to programmatically control scroll position before iOS 17. The modern replacement
/// uses `scrollPosition(id:)` with a `@State` binding, which is declarative and
/// integrates cleanly with SwiftUI's state-driven model.
final class ScrollViewReaderDeprecatedVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "ScrollViewReader" else { return .visitChildren }

        addIssue(
            severity: .info,
            message: "ScrollViewReader can be replaced with the iOS 17 scroll position API",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use .scrollPosition(id:) with a @State binding and ScrollPosition for iOS 17+.",
            ruleName: .scrollViewReaderDeprecated
        )
        return .visitChildren
    }
}

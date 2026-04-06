import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects deprecated `.cornerRadius()` modifier usage.
///
/// `.cornerRadius()` was deprecated in iOS 17. The replacement `.clipShape(.rect(cornerRadius:))`
/// uses the typed `RoundedRectangle` shape, which also unlocks `.continuous` corner style
/// and composes cleanly with other shape-based modifiers.
final class CornerRadiusDeprecatedVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "cornerRadius" else { return .visitChildren }

        addIssue(
            severity: .warning,
            message: ".cornerRadius() is deprecated in iOS 17",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use .clipShape(.rect(cornerRadius:)) or .clipShape(RoundedRectangle(cornerRadius:)) instead.",
            ruleName: .cornerRadiusDeprecated
        )
        return .visitChildren
    }
}

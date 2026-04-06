import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `.replacingOccurrences(of:with:)` calls that can use the modern
/// `.replacing(_:with:)` API introduced in Swift 5.7 (iOS 16+).
final class LegacyReplacingOccurrencesVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "replacingOccurrences",
              node.arguments.first?.label?.text == "of" else {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: ".replacingOccurrences(of:with:) is the legacy Foundation API",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use .replacing(\"old\", with: \"new\") instead (requires iOS 16+/Swift 5.7).",
            ruleName: .legacyReplacingOccurrences
        )
        return .visitChildren
    }
}

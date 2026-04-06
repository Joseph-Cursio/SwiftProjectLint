import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `UIGraphicsImageRenderer` usage that can be replaced with
/// SwiftUI's `ImageRenderer` (iOS 16+).
final class LegacyImageRendererVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "UIGraphicsImageRenderer" else {
            return .visitChildren
        }

        reportIssue(at: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: TypeAnnotationSyntax) -> SyntaxVisitorContinueKind {
        if node.type.trimmedDescription.contains("UIGraphicsImageRenderer") {
            reportIssue(at: Syntax(node))
        }
        return .visitChildren
    }

    private func reportIssue(at node: Syntax) {
        addIssue(
            severity: .info,
            message: "UIGraphicsImageRenderer is the legacy UIKit rendering API",
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "Use SwiftUI's ImageRenderer instead (requires iOS 16+).",
            ruleName: .legacyImageRenderer
        )
    }
}

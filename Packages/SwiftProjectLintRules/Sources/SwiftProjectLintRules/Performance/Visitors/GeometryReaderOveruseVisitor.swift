import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `GeometryReader` usage that may be replaceable with modern APIs.
///
/// `GeometryReader` eagerly consumes all available space and makes layout
/// inflexible. iOS 17 introduced `containerRelativeFrame()` for proportional
/// sizing and `visualEffect()` for geometry-dependent effects, both of which
/// are more composable. This rule is opt-in given the high false positive
/// surface — `GeometryReader` is sometimes legitimately necessary.
final class GeometryReaderOveruseVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "GeometryReader" else {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: "GeometryReader eagerly consumes all available space "
                + "— consider modern alternatives",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use containerRelativeFrame() for proportional sizing "
                + "or visualEffect() for geometry-dependent effects (iOS 17+).",
            ruleName: .geometryReaderOveruse
        )
        return .visitChildren
    }
}

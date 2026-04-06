import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `.tabItem { }` modifier calls that can use the modern `Tab` API
/// introduced in iOS 18.
final class TabItemDeprecatedVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "tabItem" else {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: ".tabItem { } is the legacy TabView API",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use Tab(\"Title\", systemImage: \"icon\") { Content() } "
                + "instead (requires iOS 18+).",
            ruleName: .tabItemDeprecated
        )
        return .visitChildren
    }
}

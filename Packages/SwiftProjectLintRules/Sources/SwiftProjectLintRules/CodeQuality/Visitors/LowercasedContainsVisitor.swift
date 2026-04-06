import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `.lowercased().contains(...)` and `.uppercased().contains(...)`.
///
/// These patterns perform naive case-insensitive search that ignores locale, diacritics,
/// and Unicode normalization. `localizedStandardContains()` handles all of these correctly.
final class LowercasedContainsVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        detectLowercasedContains(node)
        return .visitChildren
    }

    private func detectLowercasedContains(_ node: FunctionCallExprSyntax) {
        // Outer call must be .contains(...)
        guard let outerMember = node.calledExpression.as(MemberAccessExprSyntax.self),
              outerMember.declName.baseName.text == "contains",
              node.arguments.count == 1 else { return }

        // The base of .contains(...) must be a function call — .lowercased() or .uppercased()
        guard let baseCall = outerMember.base?.as(FunctionCallExprSyntax.self),
              let baseMember = baseCall.calledExpression.as(MemberAccessExprSyntax.self) else { return }

        let methodName = baseMember.declName.baseName.text
        guard methodName == "lowercased" || methodName == "uppercased" else { return }

        // Ensure .lowercased()/.uppercased() is called with no arguments (string version)
        guard baseCall.arguments.isEmpty else { return }

        addIssue(
            severity: .warning,
            message: ".\(methodName)().contains(...) performs naive case-insensitive search. "
                + "This ignores locale rules and diacritics.",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use .localizedStandardContains() instead — it handles case, diacritics, "
                + "and locale-specific rules automatically.",
            ruleName: .lowercasedContains
        )
    }
}

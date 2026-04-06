import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects force unwrap (`!`) expressions.
///
/// Force unwrapping an optional will crash at runtime if the value is nil.
/// Prefer `if-let`, `guard-let`, or nil-coalescing (`??`) instead.
final class ForceUnwrapVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        addIssue(
            severity: .info,
            message: "Force unwrap (!) will crash on nil — consider using if-let, guard-let, or nil-coalescing",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use if-let, guard-let, or the nil-coalescing operator (??) for safe unwrapping.",
            ruleName: .forceUnwrap
        )
        return .visitChildren
    }
}

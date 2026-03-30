import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `DispatchQueue.main.async` and `DispatchQueue.main.sync` calls.
///
/// These legacy GCD patterns can be replaced with `MainActor.run` or `@MainActor` annotations
/// for cleaner Swift concurrency integration.
final class DispatchMainAsyncVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard pattern.name == .dispatchMainAsync else { return .visitChildren }
        detectDispatchMainAsync(node)
        return .visitChildren
    }

    private func detectDispatchMainAsync(_ node: FunctionCallExprSyntax) {
        // Match DispatchQueue.main.async { } or DispatchQueue.main.sync { }
        // AST: MemberAccessExpr("async"/"sync") -> MemberAccessExpr("main") -> DeclReferenceExpr("DispatchQueue")
        guard let outerMember = node.calledExpression.as(MemberAccessExprSyntax.self) else { return }

        let methodName = outerMember.declName.baseName.text
        guard methodName == "async" || methodName == "sync" else { return }

        guard let middleMember = outerMember.base?.as(MemberAccessExprSyntax.self),
              middleMember.declName.baseName.text == "main" else { return }

        guard let declRef = middleMember.base?.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "DispatchQueue" else { return }

        addIssue(
            severity: .info,
            message: "DispatchQueue.main.\(methodName) can be replaced with MainActor.run",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Use MainActor.run { } or mark the function @MainActor instead.",
            ruleName: .dispatchMainAsync
        )
    }
}

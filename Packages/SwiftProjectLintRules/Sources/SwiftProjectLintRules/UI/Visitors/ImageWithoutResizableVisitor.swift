import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `Image(...)` with `.frame()` but no `.resizable()` in the modifier chain.
///
/// Applying `.frame()` to an `Image` without `.resizable()` has no effect on the
/// image size — the image renders at its intrinsic size and the frame just adds
/// empty space around it.
final class ImageWithoutResizableVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Look for .frame() calls
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "frame" else {
            return .visitChildren
        }

        // Walk the modifier chain backwards to find the root
        let chain = collectModifierChain(from: node)

        // Check if the root is an Image(...) call
        guard isImageCall(chain.root) else { return .visitChildren }

        // Check if .resizable() appears anywhere in the chain before .frame()
        let hasResizable = chain.modifiers.contains { $0 == "resizable" }

        if hasResizable == false {
            addIssue(
                severity: .info,
                message: "Image with .frame() but no .resizable() "
                    + "— image will render at intrinsic size",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Add .resizable() before .frame() to allow "
                    + "the image to scale to the specified dimensions.",
                ruleName: .imageWithoutResizable
            )
        }

        return .visitChildren
    }

    // MARK: - Modifier chain analysis

    private struct ModifierChain {
        let root: ExprSyntax
        let modifiers: [String]
    }

    /// Walks the nested member-access/call chain to collect modifier names
    /// and find the root expression.
    private func collectModifierChain(
        from node: FunctionCallExprSyntax
    ) -> ModifierChain {
        var modifiers: [String] = []
        var current: ExprSyntax = ExprSyntax(node)

        while true {
            if let call = current.as(FunctionCallExprSyntax.self),
               let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
                modifiers.append(memberAccess.declName.baseName.text)
                if let base = memberAccess.base {
                    current = base
                    continue
                }
            }
            break
        }

        return ModifierChain(root: current, modifiers: modifiers.reversed())
    }

    /// Returns true if the expression is an `Image(...)` or `Image(systemName:)` call.
    private func isImageCall(_ expr: ExprSyntax) -> Bool {
        guard let call = expr.as(FunctionCallExprSyntax.self),
              let declRef = call.calledExpression.as(DeclReferenceExprSyntax.self) else {
            return false
        }
        return declRef.baseName.text == "Image"
    }
}

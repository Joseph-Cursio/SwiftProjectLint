import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects `.lineLimit(1)` on dynamic text content that may truncate at
/// larger Dynamic Type sizes.
///
/// Opt-in rule — `.lineLimit(1)` is legitimate in many UI designs. This rule
/// is most useful for content-heavy views.
final class MissingDynamicTypeSupportVisitor: BasePatternVisitor {

    /// Maximum static text length considered a "short label" (suppressed).
    private static let shortLabelMaxLength = 20

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "lineLimit",
              isLineLimitOne(node.arguments) else {
            return .visitChildren
        }

        // Walk the chain to find the root and collect modifiers
        let chain = collectChain(from: node)

        // Check if root is a Text(...) with dynamic content
        guard isTextWithDynamicContent(chain.root) else {
            return .visitChildren
        }

        // Suppress if .minimumScaleFactor is in the chain (before or after lineLimit)
        if chain.modifiers.contains("minimumScaleFactor")
            || hasParentModifier(node, named: "minimumScaleFactor") {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: ".lineLimit(1) on dynamic text may truncate content "
                + "at larger Dynamic Type sizes",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Consider allowing multiple lines, adding "
                + ".minimumScaleFactor(), or providing full text "
                + "via .accessibilityLabel().",
            ruleName: .missingDynamicTypeSupport
        )
        return .visitChildren
    }

    // MARK: - Helpers

    private func isLineLimitOne(_ arguments: LabeledExprListSyntax) -> Bool {
        guard let firstArg = arguments.first,
              firstArg.label == nil,
              let intLit = firstArg.expression.as(IntegerLiteralExprSyntax.self),
              let value = Int(intLit.literal.text) else {
            return false
        }
        return value == 1
    }

    /// Checks if a modifier with the given name wraps this node (is a parent).
    private func hasParentModifier(
        _ node: FunctionCallExprSyntax,
        named name: String
    ) -> Bool {
        var current: Syntax? = Syntax(node).parent
        while let parent = current {
            if let call = parent.as(FunctionCallExprSyntax.self),
               let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self),
               memberAccess.declName.baseName.text == name {
                return true
            }
            if parent.is(CodeBlockItemSyntax.self) { break }
            current = parent.parent
        }
        return false
    }

    private struct ModifierChain {
        let root: ExprSyntax
        let modifiers: [String]
    }

    private func collectChain(from node: FunctionCallExprSyntax) -> ModifierChain {
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

    /// Returns true if the expression is a `Text(...)` call with dynamic content
    /// (variable reference or string interpolation), not a short static label.
    private func isTextWithDynamicContent(_ expr: ExprSyntax) -> Bool {
        guard let call = expr.as(FunctionCallExprSyntax.self),
              let declRef = call.calledExpression.as(DeclReferenceExprSyntax.self),
              declRef.baseName.text == "Text",
              let firstArg = call.arguments.first else {
            return false
        }

        let argExpr = firstArg.expression

        // Variable reference — dynamic content
        if argExpr.is(DeclReferenceExprSyntax.self) || argExpr.is(MemberAccessExprSyntax.self) {
            return true
        }

        // String literal — check if it's short (static label) or has interpolation
        if let stringLit = argExpr.as(StringLiteralExprSyntax.self) {
            // Has interpolation segments — dynamic
            let hasInterpolation = stringLit.segments.contains { segment in
                segment.is(ExpressionSegmentSyntax.self)
            }
            if hasInterpolation { return true }

            // Pure string — check length
            let text = stringLit.segments.compactMap { segment -> String? in
                segment.as(StringSegmentSyntax.self)?.content.text
            }.joined()
            return text.count > Self.shortLabelMaxLength
        }

        // Function call or other complex expression — likely dynamic
        if argExpr.is(FunctionCallExprSyntax.self) {
            return true
        }

        return false
    }
}

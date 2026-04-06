import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects closures with explicit type annotations on parameters where types
/// are inferrable from context (e.g., standard library higher-order functions).
///
/// Opt-in rule — some teams prefer explicit closure types for documentation.
final class LegacyClosureSyntaxVisitor: BasePatternVisitor {

    /// Higher-order functions where closure parameter types are always inferrable.
    private static let inferrableContexts: Set<String> = [
        "map", "flatMap", "compactMap", "filter", "first", "contains",
        "allSatisfy", "reduce", "sorted", "sort", "forEach",
        "prefix", "drop", "removeAll", "partition",
        "min", "max"
    ]

    /// Maximum closure body lines before suppressing (explicit types aid readability).
    private static let maxBodyLines = 10

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        guard let signature = node.signature,
              hasExplicitTypeAnnotations(signature) else {
            return .visitChildren
        }

        // Check if in an inferrable context
        guard isInInferrableContext(node) else { return .visitChildren }

        // Suppress for long closure bodies
        let bodyLineCount = node.statements.count
        if bodyLineCount > Self.maxBodyLines { return .visitChildren }

        addIssue(
            severity: .info,
            message: "Closure parameter types can be inferred "
                + "— explicit type annotations are redundant",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(signature)),
            suggestion: "Remove the explicit type annotations and let Swift "
                + "infer them from context.",
            ruleName: .legacyClosureSyntax
        )
        return .visitChildren
    }

    // MARK: - Helpers

    /// Checks if the closure signature has explicit type annotations on parameters.
    private func hasExplicitTypeAnnotations(
        _ signature: ClosureSignatureSyntax
    ) -> Bool {
        guard let paramClause = signature.parameterClause else { return false }
        switch paramClause {
        case .simpleInput:
            // Simple input like `{ x in }` — no type annotations
            return false
        case .parameterClause(let clause):
            // Full parameter clause — check for type annotations
            return clause.parameters.contains { param in
                param.type != nil
            }
        }
    }

    /// Checks if the closure is a trailing closure on a known inferrable method.
    private func isInInferrableContext(_ node: ClosureExprSyntax) -> Bool {
        // Walk up to find the enclosing function call
        var current: Syntax? = Syntax(node).parent
        while let parent = current {
            if let call = parent.as(FunctionCallExprSyntax.self) {
                // Check if this closure is the trailing closure
                if call.trailingClosure?.id == node.id {
                    return isInferrableCall(call)
                }
                // Check if this closure is an argument
                for arg in call.arguments
                    where arg.expression.as(ClosureExprSyntax.self)?.id == node.id {
                    return isInferrableCall(call)
                }
            }
            if parent.is(CodeBlockItemSyntax.self) { break }
            current = parent.parent
        }
        return false
    }

    private func isInferrableCall(_ call: FunctionCallExprSyntax) -> Bool {
        if let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return Self.inferrableContexts
                .contains(memberAccess.declName.baseName.text)
        }
        return false
    }
}

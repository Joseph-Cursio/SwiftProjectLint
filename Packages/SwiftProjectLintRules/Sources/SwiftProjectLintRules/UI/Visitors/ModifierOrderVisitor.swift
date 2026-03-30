import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation
import SwiftSyntax

/// Visitor that detects incorrect SwiftUI modifier ordering.
///
/// Certain modifiers must appear in a specific order to work correctly.
/// For example, `.background()` should come after `.clipShape()` so the
/// background is clipped to the shape. This visitor walks modifier chains
/// and flags known-bad orderings.
class ModifierOrderVisitor: BasePatternVisitor {

    /// Each rule says: if `before` appears earlier in the chain than any modifier
    /// in `after`, that's a misordering. The `reason` explains why.
    private struct OrderingRule {
        let before: String
        let after: Set<String>
        let reason: String
    }

    private static let rules: [OrderingRule] = [
        OrderingRule(
            before: "background",
            after: ["clipShape", "cornerRadius"],
            reason: "background won't be clipped to the shape"
        ),
        OrderingRule(
            before: "shadow",
            after: ["clipShape", "cornerRadius"],
            reason: "shadow won't match the clipped shape"
        ),
        OrderingRule(
            before: "border",
            after: ["clipShape"],
            reason: "border won't follow the clip shape"
        )
    ]

    /// Tracks which top-level chains we've already analyzed to avoid duplicate reports.
    private var analyzedChains: Set<SyntaxIdentifier> = []

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func reset() {
        super.reset()
        analyzedChains.removeAll()
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Only analyze from the outermost call in a chain
        guard isModifierCall(node),
              !isNestedInModifierCall(node),
              !analyzedChains.contains(node.id) else {
            return .visitChildren
        }

        analyzedChains.insert(node.id)

        let chain = extractModifierChain(from: node)
        guard chain.count >= 2 else { return .visitChildren }

        checkOrderingViolations(chain: chain)
        return .visitChildren
    }

    /// Extracts the ordered list of modifier names from a chain, from first-applied to last-applied.
    ///
    /// In SwiftSyntax, `.a().b().c()` nests as: c(b(a(base))).
    /// So we walk from outer to inner, collecting names, then reverse.
    private func extractModifierChain(from node: FunctionCallExprSyntax) -> [(name: String, node: Syntax)] {
        var chain: [(name: String, node: Syntax)] = []
        var current: ExprSyntax = ExprSyntax(node)

        while let call = current.as(FunctionCallExprSyntax.self),
              let memberAccess = call.calledExpression.as(MemberAccessExprSyntax.self) {
            let name = memberAccess.declName.baseName.text
            chain.append((name: name, node: Syntax(call)))
            // Move to the base expression (the receiver of the member access)
            if let base = memberAccess.base {
                current = base
            } else {
                break
            }
        }

        // chain is outer-to-inner (last-applied first), reverse to get application order
        return chain.reversed()
    }

    private func checkOrderingViolations(chain: [(name: String, node: Syntax)]) {
        for rule in Self.rules {
            // Find the first occurrence of the `before` modifier
            guard let beforeIndex = chain.firstIndex(where: { $0.name == rule.before }) else {
                continue
            }

            // Check if any `after` modifier appears later in the chain
            for idx in (beforeIndex + 1)..<chain.count {
                if rule.after.contains(chain[idx].name) {
                    addIssue(
                        node: chain[beforeIndex].node,
                        variables: [
                            "before": rule.before,
                            "after": chain[idx].name,
                            "reason": rule.reason
                        ]
                    )
                    break
                }
            }
        }
    }

    /// Returns true if this function call is a dot-member-style modifier call.
    private func isModifierCall(_ node: FunctionCallExprSyntax) -> Bool {
        node.calledExpression.is(MemberAccessExprSyntax.self)
    }

    /// Returns true if this node's parent is also a modifier call (meaning we're not the outermost).
    private func isNestedInModifierCall(_ node: FunctionCallExprSyntax) -> Bool {
        // Walk up: parent might be a MemberAccessExpr whose parent is a FunctionCallExpr
        guard let parent = node.parent else { return false }
        if let memberAccess = parent.as(MemberAccessExprSyntax.self),
           let grandparent = memberAccess.parent,
           grandparent.is(FunctionCallExprSyntax.self) {
            return true
        }
        return false
    }
}

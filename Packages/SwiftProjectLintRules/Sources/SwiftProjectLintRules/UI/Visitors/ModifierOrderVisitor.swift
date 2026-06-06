import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Visitor that detects incorrect SwiftUI modifier ordering.
///
/// Certain modifiers must appear in a specific order to work correctly.
/// For example, `.clipShape()` applied *before* `.background()` leaves the
/// background unclipped — `clipShape` masks only the view it is applied to,
/// so a background added afterward sits behind it at the full rectangular
/// bounds. The clipped-background idiom is `.background().clipShape()`.
/// This visitor walks modifier chains and flags known-bad orderings.
class ModifierOrderVisitor: BasePatternVisitor {

    /// Each rule says: if `before` appears earlier in the chain than any modifier
    /// in `after`, that's a misordering. The `reason` explains why.
    private struct OrderingRule {
        let before: String
        let after: Set<String>
        let reason: String
    }

    private static let rules: [OrderingRule] = [
        // A clip applied BEFORE the background leaves the background unclipped:
        // `.clipShape(S).background(B)` draws B behind the clipped view at its
        // rectangular bounds. The clipped-background idiom is the reverse,
        // `.background(B).clipShape(S)`, so that is NOT flagged.
        OrderingRule(
            before: "clipShape",
            after: ["background"],
            reason: "the background is added after the clip, so it isn't clipped to the shape"
        ),
        OrderingRule(
            before: "cornerRadius",
            after: ["background"],
            reason: "the background is added after the corner radius, so it isn't rounded"
        ),
        // A shadow applied BEFORE a clip is clipped away — clip first, then
        // shadow, so the shadow follows the clipped shape.
        OrderingRule(
            before: "shadow",
            after: ["clipShape", "cornerRadius"],
            reason: "the shadow is clipped away — apply it after the clip so it follows the shape"
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
        var current = ExprSyntax(node)

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
            for idx in (beforeIndex + 1)..<chain.count where rule.after.contains(chain[idx].name) {
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

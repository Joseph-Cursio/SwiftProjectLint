import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a stored property that is assigned a **string interpolation of its
/// sibling state fields** — `state.fullName = "\(state.firstName) \(state.lastName)"`.
/// Such a value is *derived*, not independent state; storing it means re-deriving
/// it on every relevant change and risking it going stale. The fix is a computed
/// property:
///
/// ```swift
/// var fullName: String { "\(firstName) \(lastName)" }
/// ```
///
/// **Deliberately narrow (v1), for precision:**
/// - Only **string-interpolation** derivations — the cheap, clearly-computable
///   case. Numeric aggregates (`total = a + b`, `count = items.count`) are *not*
///   flagged: they are sometimes materialized for performance, and
///   SwiftInferProperties treats `count == items.count` as a *conservation
///   invariant* worth testing, not a smell.
/// - The interpolation must reference the **same base** as the assignment target
///   (`state.fullName` ← `state.firstName`), the dominant TCA-reducer idiom.
/// - Self-referential assignments (`state.log = "\(state.log)\n\(entry)"`) are
///   appends, not derivations, and are excluded.
///
/// Fires at the derive-assignment site (no cross-statement "only ever assigned
/// this way" analysis). Motivated by a TCA state-consistency review.
final class RedundantDerivedPropertyVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Visit (both unfolded and folded assignment forms)

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        if elements.count == 3, elements[1].is(AssignmentExprSyntax.self) {
            checkAssignment(lhs: elements[0], rhs: elements[2], at: Syntax(node))
        }
        return .visitChildren
    }

    override func visit(_ node: InfixOperatorExprSyntax) -> SyntaxVisitorContinueKind {
        if node.operator.is(AssignmentExprSyntax.self) {
            checkAssignment(lhs: node.leftOperand, rhs: node.rightOperand, at: Syntax(node))
        }
        return .visitChildren
    }

    // MARK: - Detection

    private func checkAssignment(lhs: ExprSyntax, rhs: ExprSyntax, at node: Syntax) {
        guard let target = lhs.as(MemberAccessExprSyntax.self),
              let baseRef = target.base?.as(DeclReferenceExprSyntax.self),
              let stringLiteral = rhs.as(StringLiteralExprSyntax.self) else {
            return
        }
        let base = baseRef.baseName.text
        let targetName = target.declName.baseName.text

        let siblings = referencedSiblings(in: stringLiteral, base: base)
        // Must derive from at least one *other* sibling and must not reference
        // itself (that would be an append, not a derivation).
        guard siblings.contains(targetName) == false, siblings.isEmpty == false else {
            return
        }
        addIssue(node: node, variables: ["target": targetName])
    }

    /// Names `X` such that `<base>.X` appears in one of the literal's
    /// interpolation segments.
    private func referencedSiblings(in stringLiteral: StringLiteralExprSyntax, base: String) -> Set<String> {
        var refs: Set<String> = []
        for segment in stringLiteral.segments {
            guard case let .expressionSegment(expressionSegment) = segment else { continue }
            for argument in expressionSegment.expressions {
                collectBaseMembers(in: Syntax(argument.expression), base: base, into: &refs)
            }
        }
        return refs
    }

    private func collectBaseMembers(in node: Syntax, base: String, into refs: inout Set<String>) {
        if let member = node.as(MemberAccessExprSyntax.self),
           let memberBase = member.base?.as(DeclReferenceExprSyntax.self),
           memberBase.baseName.text == base {
            refs.insert(member.declName.baseName.text)
        }
        for child in node.children(viewMode: .sourceAccurate) {
            collectBaseMembers(in: child, base: base, into: &refs)
        }
    }
}

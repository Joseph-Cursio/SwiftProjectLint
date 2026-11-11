import SwiftSyntax

/// A call whose arguments are mostly reads from one value — either `other.member`, or a bare
/// `label: label` that is `self.label` with the `self.` left off.
struct Rebuild {

    /// What a rebuild-from-`self` is recorded as. Not a real identifier, so it cannot collide with
    /// one; the message renders it as `self`.
    static let implicitSelf = "self"

    /// The value being copied from.
    let base: String

    /// Whether the source is `self`, read through bare identifiers rather than named.
    var isImplicitSelf: Bool { base == Self.implicitSelf }

    /// Whether *most* of the arguments come from it.
    ///
    /// The threshold is **`m > n/2`, capped at `n − 1`**: more than half the arguments are copied
    /// from one value, and — for a small call — at least all-but-one.
    ///
    /// **The majority bar rather than a supermajority, and the reason is the failure itself.** A
    /// realistic rebuild copies every field and *changes a few*; the more it changes, the likelier
    /// one gets forgotten. So the dangerous rebuild is the one with **several** computed arguments —
    /// and a 70% bar excludes precisely that. On the eleven-field `Suggestion` that motivated this
    /// rule, a rebuild altering four fields would have slipped under a 70% threshold and been missed,
    /// while being the exact shape in which the fifth field was dropped.
    ///
    /// The `n − 1` cap keeps small calls honest: `Point(x: p.x, y: p.y, z: 0)` is 2-of-3, which is a
    /// majority *and* all-but-one, and it is a copy.
    let isDominant: Bool

    init?(
        call: FunctionCallExprSyntax,
        minimumArguments: Int,
        namesBoundLocally: Set<String>,
        allowsImplicitSelf: Bool
    ) {
        let arguments = Array(call.arguments)
        guard arguments.count >= minimumArguments else { return nil }

        var counts: [String: Int] = [:]
        for argument in arguments {
            // `label: other.member` — an explicit source value.
            if let member = argument.expression.as(MemberAccessExprSyntax.self),
               let receiver = member.base?.as(DeclReferenceExprSyntax.self) {
                counts[receiver.baseName.text, default: 0] += 1
                continue
            }

            // `label: label` — a bare identifier whose name IS the argument label. Inside the type's
            // own body that is `self.label` with the `self.` left off, and it is the form the bug
            // most often takes: `Suggestion.withExplainability` and `VerifyEvidenceScoring` both
            // rebuilt `self` this way, and both dropped a field.
            //
            // But it is only a field read if the name is NOT bound locally. `origin: origin` in a
            // factory whose parameter is `origin` reads the parameter, and a `static` function has
            // no `self` at all — both are ordinary construction, not a copy.
            guard allowsImplicitSelf else { continue }
            if let reference = argument.expression.as(DeclReferenceExprSyntax.self),
               let label = argument.label?.text,
               reference.baseName.text == label,
               !namesBoundLocally.contains(label) {
                counts[Self.implicitSelf, default: 0] += 1
            }
        }

        guard let (base, matched) = counts.max(by: { $0.value < $1.value }), matched > 0 else {
            return nil
        }

        let total = arguments.count
        let majority = total / 2 + 1        // strictly more than half
        let threshold = min(majority, total - 1)

        self.base = base
        self.isDominant = matched >= threshold
    }
}

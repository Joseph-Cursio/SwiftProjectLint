import SwiftSyntax

/// Where a `DeclReferenceExprSyntax` sits, which decides whether it is a reference at all.
///
/// SwiftSyntax spells three different things with the same node. In `job.name` and in
/// `rules.map(\.name)`, `name` is a `DeclReferenceExprSyntax` exactly as a bare `name` is, but
/// neither of the first two looks `name` up in scope: one is a member of `job`, the other a member
/// of the key path's root type. A visitor that asks "does this body use the parameter, local or
/// stored property called `name`?" by matching on `baseName` alone answers yes to all three.
///
/// The mistake was made independently in `SelfAccessAnalyzer` and then in eight rules, which took
/// a key-path component or someone else's member for a use of a `Bool` parameter, a caught
/// `error`, a stored property or a local binding. These predicates are the one place the question
/// is answered.
///
/// Only the *name* is ever excluded. The arguments of a subscript component (`index` in
/// `\.[index]`) and the base of a member access (`job` in `job.name`) are separate nodes and stay
/// genuine references.
extension DeclReferenceExprSyntax {

    /// Whether this is the name of a key-path property component: `name` in `\.name`,
    /// `\Row.name` or `\.name.count`.
    ///
    /// The name belongs to the key path's root type, the value a closure in the same position
    /// would have received, and never to the scope the key path is written in.
    ///
    /// Property components only. Method components (`\.uppercased()`) are an experimental
    /// language feature behind swift-syntax's `ExperimentalLanguageFeatures` SPI, and the default
    /// parser does not produce them: it reads `\.uppercased()` as a call applied to the property
    /// key path `\.uppercased`, which this already covers.
    public var isKeyPathComponentName: Bool {
        guard let component = parent?.as(KeyPathPropertyComponentSyntax.self) else { return false }
        return component.declName.id == id
    }

    /// Whether this is the member half of a member access, on any base: `name` in `job.name`,
    /// `self.name`, `Self.name` or the implicit `.name`.
    ///
    /// The right question for a parameter or a local. Neither can be reached through a dot, so
    /// no member access — not even through `self` — refers to one.
    public var isMemberName: Bool {
        guard let access = parent?.as(MemberAccessExprSyntax.self) else { return false }
        return access.declName.id == id
    }

    /// Whether this is the member half of a member access whose base is not this instance:
    /// `name` in `job.name`, `Self.name`, or the implicit `.name`.
    ///
    /// The right question for a stored property, which a body reaches either bare or through
    /// `self` — including `self?.name` in a `[weak self]` closure, and `(self).name`. A member of
    /// anything else belongs to that other value or type, and a static member is not instance
    /// state.
    public var isMemberNameOfOtherBase: Bool {
        guard let access = parent?.as(MemberAccessExprSyntax.self), access.declName.id == id else {
            return false
        }
        guard var base = access.base else { return true }
        while let unwrapped = base.as(OptionalChainingExprSyntax.self)?.expression
            ?? base.as(ForceUnwrapExprSyntax.self)?.expression
            ?? Self.parenthesized(base) {
            base = unwrapped
        }
        return base.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind != .keyword(.self)
    }

    /// The expression inside `(expression)` — a one-element tuple with no label, which is how
    /// swift-syntax spells parentheses.
    private static func parenthesized(_ expression: ExprSyntax) -> ExprSyntax? {
        guard let tuple = expression.as(TupleExprSyntax.self), tuple.elements.count == 1,
              let only = tuple.elements.first, only.label == nil else { return nil }
        return only.expression
    }

    /// Whether this names something looked up in lexical scope — a local, a parameter, or a
    /// member reached through implicit `self` — rather than a member name or a key-path component.
    ///
    /// The question every "does this body use `name`?" check means when `name` is a parameter or a
    /// local binding.
    public var isLexicalReference: Bool {
        isKeyPathComponentName == false && isMemberName == false
    }
}

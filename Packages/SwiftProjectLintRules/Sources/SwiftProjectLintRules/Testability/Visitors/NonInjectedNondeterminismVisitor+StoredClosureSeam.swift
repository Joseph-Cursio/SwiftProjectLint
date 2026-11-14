import SwiftSyntax

/// The stored-property half of the injection seam: a replaceable closure property's production
/// default.
///
/// In its own file because the placement extension is at its length limit, and because it is the
/// counterpart of `isParameterDefaultValue` rather than a placement fact of its own.
extension NonInjectedNondeterminismVisitor {

    /// True when `node` sits in an uninvoked closure that is the initial value of a stored `var`
    /// member nothing restricts writing to: `var now: Now = { Date() }`.
    ///
    /// ## The same seam as a parameter default
    ///
    /// A parameter default is exempt because it is substitutable by construction: a test passes
    /// `{ fixedDate }` instead. A stored `var` holding a closure is substitutable the same way, and
    /// by the same party. A test that can reach the value can write `world.now = { fixedDate }`,
    /// and in a struct with no hand-written initialiser the property *is* a parameter default,
    /// because the memberwise initialiser takes it with `{ Date() }` as its default. Where a
    /// test cannot reach the value, because the code under test builds its own, neither seam helps,
    /// so the two fail together too.
    ///
    /// The corpus instance is a dependency-injection container, SwiftMutator's `World`:
    ///
    /// ```swift
    /// struct World: Sendable {
    ///     var now: Now = { Date() }      // typealias Now = @Sendable () -> Date
    /// ```
    ///
    /// It was told to "inject the source", which is what the line already is.
    ///
    /// ## What the gate reads
    ///
    /// The declared type is often a typealias, as `Now` is there, and a typealias is not resolvable
    /// from one file's syntax. The gate reads the initial value instead: a closure literal that is
    /// the whole initial value, not called, can only initialise a function-typed property. Then it
    /// asks whether anyone outside the declaration can replace it:
    /// - **`var`**, not `let`. A `let` with an initial value is fixed for every instance; no
    ///   initialiser can assign it, so nothing can substitute it.
    /// - **A member**, not a local. A local closure is replaceable only by the code around it.
    /// - **Not `private` or `fileprivate`**, including `private(set)`. A test cannot write it.
    /// - **Stored**: no accessor block, observers included. Failing toward the report is the
    ///   safe direction, and an observed closure property is not a shape the corpus has.
    ///
    /// **Called closures are refused, and that is the line.** `lazy var stamp = { Date() }()` runs
    /// the closure and stores a `Date`, which is a value and not a seam. So is a provider built
    /// from a closure, `static let live = DateProvider { Date() }`: the closure there is an
    /// argument, and whether the result is substitutable depends on a type this rule cannot see.
    /// That shape stays declined on the rule page.
    func isReplaceableStoredClosure(_ node: Syntax) -> Bool {
        var current = node.parent
        while let syntax = current {
            // Mirrors `isParameterDefaultValue`: a body between the read and the seam is code that
            // runs, not a value being handed over.
            if syntax.is(CodeBlockSyntax.self) || syntax.is(AccessorBlockSyntax.self) { return false }
            if let closure = syntax.as(ClosureExprSyntax.self),
               let clause = closure.parent?.as(InitializerClauseSyntax.self),
               Syntax(clause.value).id == Syntax(closure).id {
                return Self.isReplaceableStoredMember(clause)
            }
            current = syntax.parent
        }
        return false
    }

    /// Whether the property `clause` initialises is a stored `var` member a test can write.
    private static func isReplaceableStoredMember(_ clause: InitializerClauseSyntax) -> Bool {
        guard let binding = clause.parent?.as(PatternBindingSyntax.self),
              binding.accessorBlock == nil,
              let declaration = binding.parent?.parent?.as(VariableDeclSyntax.self),
              declaration.bindingSpecifier.tokenKind == .keyword(.var),
              declaration.parent?.is(MemberBlockItemSyntax.self) == true else { return false }
        return !declaration.modifiers.contains { modifier in
            modifier.name.tokenKind == .keyword(.private)
                || modifier.name.tokenKind == .keyword(.fileprivate)
        }
    }
}

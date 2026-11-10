import SwiftSyntax

/// Where a closure lives, for a finding whose subject has no name of its own.
///
/// **Shared by both closure rules for the same reason the call-site vocabulary is.** A census
/// finding and an inventory finding at the same call site must name the same enclosing member, or a
/// reader comparing the two lists is comparing different coordinates.
enum EnclosingDeclaration {

    /// The declaration the closure is trapped inside — `fetchLocalFiles`, `filteredFiles`.
    ///
    /// **This is a location, not a subject, and that is the whole point.** The finding is a closure,
    /// which by definition *has no name* — that is what the rule is complaining about. `filter` and
    /// `sorted` name the operation, not the code, and every `filter` in a codebase would share the
    /// symbol. A downstream consumer that narrowed analysis to `filter` would be narrowing to
    /// nothing.
    ///
    /// So the symbol names the enclosing declaration, on exactly the terms `extractableTotalKernel`
    /// already uses: *here is where to look*, and a human draws the boundary. `PBTSeedKind` calls
    /// this shape `refactor-pending`, and a consumer must not point analysis at it.
    ///
    /// A computed property counts. `filteredFiles` is a `var` with a body, and the search predicate
    /// hiding inside it is as extractable as the one inside `fetchLocalFiles` — refusing it because
    /// it is spelled `var` would be a distinction the reader does not care about.
    ///
    /// **A local binding does not count**, and the difference is not pedantry. Written naively, the
    /// walk stops at the nearest `VariableDeclSyntax` — which for
    ///
    ///     let immediateChildren = allFiles.filter { … }
    ///
    /// is the local `let`, so the seed comes out named `immediateChildren`: a name that exists
    /// nowhere a consumer can look it up, and that changes the moment someone renames a local. The
    /// seed must name something a reader can *navigate to*, which means the enclosing **member** —
    /// so a local binding is stepped over and the walk continues to `fetchLocalFiles`.
    static func name(of node: some SyntaxProtocol) -> String? {
        var parent = node.parent
        while let current = parent {
            if let function = current.as(FunctionDeclSyntax.self) {
                return function.name.text
            }
            if let variable = current.as(VariableDeclSyntax.self), isMemberDeclaration(variable) {
                return variable.bindings
                    .lazy
                    .compactMap { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text }
                    .first
            }
            parent = current.parent
        }
        return nil
    }

    /// A stored or computed property, as opposed to a `let` inside a function body.
    ///
    /// A member declaration sits directly in a type's `MemberBlockItemList`; a local binding sits in
    /// a `CodeBlockItemList`. That parent is the only thing that distinguishes them — the two share a
    /// syntax node — so it is what the check asks about.
    static func isMemberDeclaration(_ variable: VariableDeclSyntax) -> Bool {
        variable.parent?.is(MemberBlockItemSyntax.self) ?? false
    }
}

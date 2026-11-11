import SwiftSyntax

extension SelfAccessAnalyzer {
    // MARK: - Local bindings

    /// Every name bound inside `method`: its parameters, and every pattern bound in its body —
    /// `let`/`var` declarations, `if let`/`guard let`, `for … in`, `case let`, closure parameters.
    static func locallyBoundNames(of method: FunctionDeclSyntax) -> Set<String> {
        var names: Set<String> = []

        for parameter in method.signature.parameterClause.parameters {
            // The *internal* name is what the body uses: in `for file: MacCloudFile`, the body
            // says `file`, not `for`.
            let internalName = parameter.secondName?.text ?? parameter.firstName.text
            if internalName != "_" { names.insert(internalName) }
        }

        if let body = method.body {
            let collector = LocalBindingCollector(viewMode: .sourceAccurate)
            collector.walk(body)
            names.formUnion(collector.names)
        }
        return names
    }

    final class LocalBindingCollector: SyntaxVisitor {
        var names: Set<String> = []

        /// **A shorthand optional binding is not a binding, it is a read.**
        ///
        /// Swift 5.7's `if let tagFilter` — no `=` — takes its value from whatever `tagFilter`
        /// already meant, so the name is not introduced here and must not be recorded as local.
        /// Leaving it out is the whole fix: the reference then falls through to
        /// `resolveSelfProperty`, which admits a stored `let` as `.immutableSelf` and refuses a
        /// stored `var` — the same answer the explicit `if let filter = self.tagFilter` spelling
        /// already got. Recording it made a method reading mutable instance state report as a
        /// function of its inputs, and seeded it into a manifest whose contract is that it names
        /// pure functions (SwiftProjectLint#215).
        ///
        /// Nothing is lost in the legitimate shadowing case. `let value = compute()` followed by
        /// `if let value` still resolves as a local, because the `let` bound the name and this
        /// set is a union over the whole body — the shorthand had nothing to add. A parameter is
        /// the same. What is left over is a name neither local nor a visible stored property — a
        /// global, or a property declared in another file — and that refuses, which is this
        /// analyzer's stated posture for everything it cannot see.
        override func visit(_ node: IdentifierPatternSyntax) -> SyntaxVisitorContinueKind {
            guard Self.isShorthandOptionalBinding(node) == false else { return .visitChildren }
            names.insert(node.identifier.text)
            return .visitChildren
        }

        /// Whether `node` is the whole pattern of an `if let x` / `guard let x` with no initializer.
        ///
        /// SwiftSyntax models the shorthand as an `OptionalBindingConditionSyntax` whose
        /// `initializer` is `nil` and whose `pattern` is this identifier. The `= expr` form is a
        /// genuine new binding and stays in `names`: there the name on the left is the author's
        /// choice and the thing being read is spelled out on the right, where it is classified on
        /// its own.
        static func isShorthandOptionalBinding(_ node: IdentifierPatternSyntax) -> Bool {
            guard let condition = node.parent?.as(OptionalBindingConditionSyntax.self),
                  Syntax(condition.pattern).id == Syntax(node).id else { return false }
            return condition.initializer == nil
        }

        override func visit(_ node: ClosureShorthandParameterSyntax) -> SyntaxVisitorContinueKind {
            names.insert(node.name.text)
            return .visitChildren
        }

        override func visit(_ node: ClosureParameterSyntax) -> SyntaxVisitorContinueKind {
            names.insert(node.secondName?.text ?? node.firstName.text)
            return .visitChildren
        }
    }
}

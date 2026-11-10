import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

extension NonInjectedNondeterminismVisitor {
    /// A nondeterministic source sitting as the fallback of a `??`, together
    /// with the expression whose absence it stands in for.
    ///
    /// `missing` is what makes the lazy-creation gate possible: knowing *which*
    /// value was nil is what lets a later statement be recognised as putting
    /// the invented one back where it belongs. It is empty when the left
    /// operand is not a plain reference, because a call or a literal is not
    /// something a later statement can write into.
    struct Fallback {
        let missing: String
        /// The `??` chain's element list when the tree is unfolded; `nil` for a
        /// folded tree, where the self-assignment form cannot be read off a
        /// sibling list.
        let elements: ExprListSyntax?
        let expression: Syntax
    }

    /// The `??` fallback `node` **is**, or `nil` when it is not one.
    ///
    /// Handles both spellings because the tree shape depends on who parsed it.
    /// `SwiftParser` leaves `a ?? b` as a `SequenceExprSyntax` of three
    /// elements; a caller that has folded operators hands over an
    /// `InfixOperatorExprSyntax`. Reading only the folded form would make this
    /// silently report nothing under the parser the tests and the CLI both use.
    ///
    /// ## Being the fallback, not sitting inside one
    ///
    /// The walk climbs only through *transparent* wrappers — parentheses,
    /// `try`, `await` — and stops at anything else. That distinction is the
    /// whole rule, and the first version of this got it wrong: an unrestricted
    /// walk reported the `UUID()` in
    ///
    /// ```swift
    /// userDefaults ?? UserDefaults(suiteName: "test.\(UUID().uuidString)") ?? .standard
    /// ```
    ///
    /// as a fabrication, because a `??` sits somewhere above it. Nothing is
    /// fabricated there: the fallback is a fresh isolated suite, and the UUID
    /// is a genuine identity doing its job. Caught by running the corpus rather
    /// than by the unit tests, which had only covered the closure form of the
    /// same mistake.
    ///
    /// The reachable-source case — `cached ?? recompute { Date() }` — is the
    /// same shape and now falls out of the same check rather than needing the
    /// closure stop to catch it. That stop is kept anyway: it is cheap, and it
    /// states the intent at the boundary a reader looks for it.
    func nilCoalescingFallback(containing node: Syntax) -> Fallback? {
        var current = node
        while let parent = current.parent {
            if parent.is(ClosureExprSyntax.self) || parent.is(CodeBlockSyntax.self) { return nil }

            if let infix = parent.as(InfixOperatorExprSyntax.self) {
                guard isNilCoalescing(infix.operator),
                      Syntax(infix.rightOperand).id == current.id else { return nil }
                return Fallback(
                    missing: reference(infix.leftOperand), elements: nil, expression: Syntax(infix)
                )
            }
            if let elements = parent.as(ExprListSyntax.self),
               let sequence = elements.parent?.as(SequenceExprSyntax.self) {
                guard let missing = missingOperand(before: current, in: elements) else { return nil }
                return Fallback(
                    missing: missing, elements: elements, expression: Syntax(sequence)
                )
            }
            guard isTransparentWrapper(parent) else { return nil }
            current = parent
        }
        return nil
    }

    /// True when `syntax` wraps an expression without changing which expression
    /// it *is* — parentheses, `try`, `await`.
    ///
    /// A parenthesised expression parses as a one-element `TupleExprSyntax`, so
    /// the arity and label checks are what separate `(Date())` from
    /// `f(at: Date())`. Without them this would re-admit every call argument and
    /// the walk would be unrestricted again.
    func isTransparentWrapper(_ syntax: Syntax) -> Bool {
        if syntax.is(TryExprSyntax.self) || syntax.is(AwaitExprSyntax.self) { return true }
        if let tuple = syntax.as(TupleExprSyntax.self) { return tuple.elements.count == 1 }
        if let element = syntax.as(LabeledExprSyntax.self) {
            return element.label == nil && element.parent?.parent?.is(TupleExprSyntax.self) == true
        }
        if let list = syntax.as(LabeledExprListSyntax.self) {
            return list.parent?.is(TupleExprSyntax.self) == true
        }
        return false
    }

    /// The operand immediately left of the `??` that `element` follows, or
    /// `nil` when `element` is not a fallback at all.
    ///
    /// The predecessor rather than the position, so `a ?? b ?? c` treats both
    /// `b` and `c` as fallbacks — each is the value used when everything to its
    /// left was absent — and each gets the operand it actually stands in for.
    private func missingOperand(before element: Syntax, in elements: ExprListSyntax) -> String? {
        var previous: ExprSyntax?
        var beforePrevious: ExprSyntax?
        for expression in elements {
            if Syntax(expression).id == element.id {
                guard let previous, isNilCoalescing(previous) else { return nil }
                return reference(beforePrevious)
            }
            beforePrevious = previous
            previous = expression
        }
        return nil
    }

    func isNilCoalescing(_ expression: ExprSyntax) -> Bool {
        expression.as(BinaryOperatorExprSyntax.self)?.operator.text == "??"
    }

    /// `expression` as a plain reference — an identifier or member chain, with a
    /// leading `self.` stripped so `self.x` and `x` are the same storage — or
    /// `""` for anything else.
    ///
    /// A call, a literal or a subscript is deliberately not a reference here:
    /// nothing a later statement writes to can be matched against it, so the
    /// lazy-creation gate stays shut rather than guessing.
    private func reference(_ expression: ExprSyntax?) -> String {
        guard let expression,
              expression.is(DeclReferenceExprSyntax.self)
                || expression.is(MemberAccessExprSyntax.self)
                || expression.is(OptionalChainingExprSyntax.self) else { return "" }
        let text = expression.trimmedDescription
        return text.hasPrefix("self.") ? String(text.dropFirst("self.".count)) : text
    }

    /// True when the invented value is written back into the thing that was
    /// missing — which makes it a created value rather than a fabricated one.
    ///
    /// ```swift
    /// let sessionID = currentSessionID ?? UUID()   // no session yet, so make one
    /// …
    /// currentSessionID = sessionID                 // and it is now the session
    /// ```
    ///
    /// **The write-back is the whole distinction, and it is not cosmetic.** Every
    /// fabrication defect in the corpus shares one property: the invented value
    /// stands in for a real one that exists somewhere else, so the two can
    /// disagree — a UUID matching no row, a date the file system has and the
    /// record does not. When the value is stored back, there is no other value
    /// for it to disagree with. It *becomes* the answer, and nothing downstream
    /// can be misled about what it was.
    ///
    /// The direct form `current = current ?? UUID()` is the same thing said in
    /// one statement, and is read off the sibling list because `SwiftParser`
    /// leaves the assignment and the `??` in a single flat sequence.
    ///
    /// A finding suppressed here is not silenced: it falls through to the
    /// rule's ordinary message, which is the true one. A test cannot pin the
    /// id; it just is not being invented. That is why this gate moved the
    /// corpus count by zero.
    func isLazyCreation(_ fallback: Fallback) -> Bool {
        guard !fallback.missing.isEmpty else { return false }

        if let elements = fallback.elements, assigns(to: fallback.missing, in: elements) {
            return true
        }
        guard let name = boundName(of: fallback.expression),
              let scope = enclosingBody(of: fallback.expression) else { return false }
        return writesBack(name, to: fallback.missing, in: scope)
    }

    /// True for `target = target ?? …` — an assignment whose left-hand side is
    /// the operand the `??` falls back from, in the same flat sequence.
    func assigns(to target: String, in elements: ExprListSyntax) -> Bool {
        var previous: ExprSyntax?
        for expression in elements {
            if expression.is(AssignmentExprSyntax.self), reference(previous) == target {
                return true
            }
            previous = expression
        }
        return false
    }

    /// The name `expression` initialises, when it is the whole initialiser of a
    /// simple `let`/`var` binding.
    private func boundName(of expression: Syntax) -> String? {
        guard let initializer = expression.parent?.as(InitializerClauseSyntax.self),
              let binding = initializer.parent?.as(PatternBindingSyntax.self) else { return nil }
        return binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
    }

    /// The nearest enclosing statement body — the scope a write-back has to
    /// live in to be this binding's.
    private func enclosingBody(of expression: Syntax) -> Syntax? {
        var current = expression.parent
        while let syntax = current {
            if syntax.is(CodeBlockSyntax.self) { return syntax }
            current = syntax.parent
        }
        return nil
    }

    /// True when `scope` contains `target = name` anywhere beneath it.
    ///
    /// The whole subtree rather than the top-level statements, because the
    /// write-back is as likely to sit inside an `if`, a `do` or a `defer` as it
    /// is to sit flat in the body.
    func writesBack(_ name: String, to target: String, in scope: Syntax) -> Bool {
        if let elements = scope.as(ExprListSyntax.self),
           isWriteBack(name, to: target, in: elements) { return true }

        if let infix = scope.as(InfixOperatorExprSyntax.self),
           infix.operator.is(AssignmentExprSyntax.self),
           reference(infix.leftOperand) == target,
           reference(infix.rightOperand) == name { return true }

        for child in scope.children(viewMode: .sourceAccurate) where writesBack(name, to: target, in: child) {
            return true
        }
        return false
    }

    func isWriteBack(_ name: String, to target: String, in elements: ExprListSyntax) -> Bool {
        var previous: ExprSyntax?
        var beforePrevious: ExprSyntax?
        for expression in elements {
            if previous?.is(AssignmentExprSyntax.self) == true,
               reference(beforePrevious) == target,
               reference(expression) == name {
                return true
            }
            beforePrevious = previous
            previous = expression
        }
        return false
    }
}

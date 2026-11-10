import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// The two syntactic questions both freeness checks need to ask.
/// A closure that does nothing but hand its arguments to a function **this project already
/// declares** — `{ search.matches(name: $0.name) }`, `{ FileListing.precedes($0, $1) }`.
///
/// ## The bug this exists to fix: the loop did not converge
///
/// The rule tells a reader to lift a closure's logic into a named function. When they do, the call
/// site they leave behind is *itself a closure* — a forwarding one — and the rule reported it again,
/// saying "extract it into a named value type" about a closure whose whole body is a call to the
/// value type they created one step earlier. All three cold readers hit this; one walked the loop
/// three times before stopping. **A rule that cannot recognise its own advice being taken never
/// terminates.**
///
/// ## Why this needs project-wide knowledge, and cannot be decided locally
///
/// These two closures are **the same shape** — one call, plain operands:
///
///     { $0.name.localizedCaseInsensitiveContains(query) }   // must still fire
///     { search.matches(name: $0.name) }                     // must not
///
/// No local analysis separates them, and the difference is not syntactic but a fact about ownership.
/// `matches(name:)` is **ours**: it is declared here, the linter already seeds it, and `swift-infer`
/// already proposes laws for it — the boundary has been drawn, and there is nothing left to extract.
/// `localizedCaseInsensitiveContains` is Foundation's: it cannot be seeded, so the law has to be
/// stated *at the closure* or nowhere, and every locale bug that hides in one is the reason the rule
/// errs toward firing on call-shaped predicates in the first place. `DeclaredFunctionCollector`
/// supplies the one fact that tells them apart.
///
/// ## What still fires
///
/// Only a **bare** forward is exempt. The instant the closure does any work of its own around the
/// call, it is expressing a rule again, and a rule can be wrong:
///
///     { search.matches(name: $0.name) && !$0.isHidden }   // fires: a conjunction is a decision
///     { search.matches(name: $0.name.uppercased()) }      // fires: `uppercased()` is logic
///
/// Matching is on the **labelled** name (`matches(name:)`), not the bare one, so exempting a call
/// requires the project to declare a function with the same name *and* the same argument labels —
/// a far narrower coincidence than a name alone.
enum ForwardingCall {

    static func describes(
        _ closure: ClosureExprSyntax,
        declaredInProject declared: Set<String>
    ) -> Bool {
        guard !declared.isEmpty,
              closure.statements.count == 1,
              let expression = ClosureBody.soleExpression(of: closure),
              let call = expression.as(FunctionCallExprSyntax.self),
              let name = labelledName(of: call)
        else { return false }

        guard declared.contains(name) else { return false }

        // Every argument must be handed over as-is. `uppercased()` inside one is logic that lives in
        // the closure and nowhere else, and it is exactly the sort of thing that comes out wrong.
        guard call.arguments.allSatisfy({ isForwarded($0.expression) }) else { return false }

        return usesEveryParameter(of: closure, in: call)
    }

    /// Every parameter the closure declares must reach the call.
    ///
    /// Per-argument coherence is not enough, and the case that proves it slipped past my first cut:
    ///
    ///     .sorted { a, b in precedes(Key(name: b.name), Key(name: b.name)) }   // `a` is never used
    ///
    /// Each projection there draws from a single base, so each is individually "coherent" — and the
    /// comparator ignores its left operand entirely. That is a real bug, and one **no law on
    /// `precedes` can see**, because the law is checked against generated keys and never runs this
    /// adapter. Exempting it would be silencing the only rule that could have spoken.
    ///
    /// What this still cannot catch is a *reversed* projection — `precedes(Key(b…), Key(a…))` — and
    /// that is deliberate: it is indistinguishable from a descending sort, which is a thing people
    /// legitimately write.
    static func usesEveryParameter(
        of closure: ClosureExprSyntax,
        in call: FunctionCallExprSyntax
    ) -> Bool {
        let parameters = parameterNames(of: closure)
        guard !parameters.isEmpty else { return true }

        let referenced = Set(call.tokens(viewMode: .sourceAccurate).map(\.text))
        return parameters.isSubset(of: referenced)
    }

    /// `{ a, b in … }` → `["a", "b"]`. Shorthand (`$0`, `$1`) is not declared, so it yields nothing —
    /// and a shorthand closure cannot fail to reference a parameter it never named.
    private static func parameterNames(of closure: ClosureExprSyntax) -> Set<String> {
        guard let signature = closure.signature else { return [] }

        switch signature.parameterClause {
        case .simpleInput(let shorthand):
            return Set(shorthand.map(\.name.text).filter { $0 != "_" })

        case .parameterClause(let clause):
            return Set(
                clause.parameters
                    .map { $0.secondName?.text ?? $0.firstName.text }
                    .filter { $0 != "_" }
            )

        case .none:
            return []
        }
    }

    /// Reconstruct the callee's Swift name from the call site: `precedes(a, b)` → `precedes(_:_:)`.
    ///
    /// **Free-shape callees only** (`foo(…)`, not `base.foo(…)`), which is the same restriction
    /// `PackagePurityJoin` placed on itself for the same reason, in this package, next door:
    ///
    /// > name-keying has been the dominant defect in three separate measurements of this seam,
    /// > most sharply when a cascade let one refuted `classify` speak for six unrelated ones.
    ///
    /// A member call cannot be resolved here — this is a per-file visitor with no type
    /// information — so `set.contains(x)` and `myCatalog.contains(x)` were the same key. Adding
    /// `ClosureWrapperTypeCatalog.contains(_:)` to an unrelated file removed **49 closure
    /// candidates** from this repository's census, silently, with a falling number as the only
    /// symptom (#185).
    ///
    /// ## The cost, measured before choosing
    ///
    /// Restricting to free shape restores **86** closures across three repositories — 3 here, 61 in
    /// SwiftInferProperties, 22 in SwiftAssist. Reading what they forward to:
    ///
    /// | name | count | |
    /// |---|---|---|
    /// | `contains` | 53 | the standard library's |
    /// | `first`, `lowercased`, `map`, `min`, `sorted` | ~24 | also the standard library's |
    /// | `matches`, `isCollection`, `isOptional`, … | ~13 | genuinely project-declared |
    ///
    /// So the member arm was **roughly six collisions for every genuine forward**. The ~13 lose
    /// their exemption and are reported again, which is the honest price: a closure forwarding to
    /// a distinctively-named project method now earns a "consider extracting" it does not need.
    /// The alternative was 77 candidates hidden by a name nobody chose for that reason.
    ///
    /// A denylist of standard-library names was the other candidate and is **not** taken: the
    /// `ConcreteTypeUsage` pass found denylists failing twice on exactly this kind of question,
    /// and a list needs an entry for every collision anyone will ever write.
    private static func labelledName(of call: FunctionCallExprSyntax) -> String? {
        let base: String
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            guard memberCallIsResolvable(member, call: call) else { return nil }
            base = member.declName.baseName.text
        } else if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            base = reference.baseName.text
        } else {
            return nil
        }

        let labels = call.arguments.map { "\($0.label?.text ?? "_"):" }.joined()
        return "\(base)(\(labels))"
    }

    /// Whether a member call names something specific enough to key on.
    ///
    /// `set.contains(x)` and `myCatalog.contains(x)` produce the same key, and this is a per-file
    /// visitor with no type information to tell them apart. Two shapes are specific enough:
    ///
    /// - **A capitalized base** — `FileOrdering.precedes(a, b)` is a static call on a type, and a
    ///   type name is not something a value happens to share with `Set`.
    /// - **At least one argument label** — `search.matches(name: $0.name)` is `matches(name:)`,
    ///   which the project must also declare for the exemption to apply. A labelled name is a far
    ///   narrower coincidence than a bare one.
    ///
    /// What is excluded is the unlabelled call on a lowercase base — `contains(_:)`, `map(_:)`,
    /// `lowercased()` — which is where every collision in #185 lived. Adding
    /// `ClosureWrapperTypeCatalog.contains(_:)` to an unrelated file removed 49 closure candidates
    /// from this repository's census, silently.
    static func memberCallIsResolvable(
        _ member: MemberAccessExprSyntax,
        call: FunctionCallExprSyntax
    ) -> Bool {
        if let base = member.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text.first?.isUppercase == true {
            return true
        }
        return call.arguments.contains { $0.label != nil }
    }

    /// An argument passed straight through: `$0`, `$0.name`, `file.path`, a capture, a literal —
    /// or a **coherent projection** of one of them (below).
    ///
    /// Anything that *computes* — an operator, `uppercased()` — is the closure doing work of its own,
    /// and work can be wrong.
    static func isForwarded(_ expression: ExprSyntax) -> Bool {
        if ClosureBody.memberPath(of: expression) != nil { return true }
        if expression.is(DeclReferenceExprSyntax.self) { return true }

        if let call = expression.as(FunctionCallExprSyntax.self) {
            return isCoherentProjection(call)
        }

        return expression.is(StringLiteralExprSyntax.self)
            || expression.is(IntegerLiteralExprSyntax.self)
            || expression.is(FloatLiteralExprSyntax.self)
            || expression.is(BooleanLiteralExprSyntax.self)
    }

    /// A call that repackages **one** value's fields and nothing else —
    /// `FileSortKey(isFolder: file1.isFolder, name: file1.name)`.
    ///
    /// ## Why this must be allowed
    ///
    /// After extracting the comparator, the call site a reader is left with is
    ///
    ///     .sorted { a, b in FileOrdering.precedes(FileSortKey(a…), FileSortKey(b…)) }
    ///
    /// The comparator is named. What remains is the *adapter* — and a rule that refuses to see it as
    /// plumbing never converges, because extracting the projection just yields another nested call,
    /// forever. `sortKey(of: $0)` is no more "extracted" than `FileSortKey($0.…)` is.
    ///
    /// ## Why it must be *coherent*
    ///
    /// The law on `precedes` is checked against **generated** `FileSortKey`s, so it never sees this
    /// projection — which means a transposition here is caught by no law at all:
    ///
    ///     FileSortKey(isFolder: file1.isFolder, name: file2.name)   // ← a real bug, invisible to the law
    ///
    /// So the exemption holds only while every field comes from the **same** source. Mix two
    /// parameters inside one projection and the closure is expressing a relation again — it fires,
    /// and it should.
    static func isCoherentProjection(_ call: FunctionCallExprSyntax) -> Bool {
        var bases: Set<String> = []

        for argument in call.arguments {
            if let path = ClosureBody.memberPath(of: argument.expression) {
                bases.insert(path.base)
                continue
            }
            if let reference = argument.expression.as(DeclReferenceExprSyntax.self) {
                bases.insert(reference.baseName.text)
                continue
            }
            guard argument.expression.is(StringLiteralExprSyntax.self)
                || argument.expression.is(IntegerLiteralExprSyntax.self)
                || argument.expression.is(FloatLiteralExprSyntax.self)
                || argument.expression.is(BooleanLiteralExprSyntax.self)
            else { return false }
        }

        // Every field drawn from one value (literals contribute no base, so a constant field is
        // fine). Two or more bases means the projection is *combining*, and that is a decision.
        return bases.count <= 1
    }
}

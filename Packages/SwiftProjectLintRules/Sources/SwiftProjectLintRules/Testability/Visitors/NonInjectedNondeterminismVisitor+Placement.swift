import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Where an expression sits, which is what separates a use from a seam.
///
/// These are facts about placement rather than about the expression, so they belong to this
/// rule's contract rather than to the shared classifier. They live in an extension because the
/// visitor's own body is at its length limit, and because they read as one group: each one
/// answers *what is this expression to the declaration around it?*
extension NonInjectedNondeterminismVisitor {

    /// The name of the computed property whose getter `node` sits in, or `nil`.
    ///
    /// Both spellings count — the implicit getter `var now: Date { Date() }`
    /// and the explicit `var now: Date { get { Date() } }` — because they are
    /// the same declaration and the same fresh read.
    ///
    /// A *stored* property is not this: `let stamp = Date()` is one read at
    /// initialisation, which is a value, and the rule's ordinary message is the
    /// right one for it. The walk therefore looks for an accessor block and
    /// stops at anything that introduces a body of its own — a nested function,
    /// an initialiser, a closure — so a clock read inside a helper declared
    /// within a getter is attributed where it is written rather than to the
    /// property enclosing it.
    ///
    /// ## The read has to *be* the property
    ///
    /// The getter must be a single expression, and that requirement came out of
    /// the corpus rather than out of these tests. Without it the check reported
    ///
    /// ```swift
    /// var body: some View {
    ///     let now = Date()          // ← reported as a fresh read per access
    ///     return … summary(asOf: now) … content(asOf: now) …
    /// }
    /// ```
    ///
    /// which is `WaiversView` *after* the fix this message exists to describe:
    /// one read, bound, threaded. Naming the enclosing property is wrong there
    /// twice over — the read happens once per evaluation, and `body` is not
    /// what anyone reads repeatedly.
    ///
    /// A multi-statement getter has already given the value a name, which is
    /// the whole remedy. What is left is the shape where the property *is* the
    /// read, so the name is the only thing standing between a reader and the
    /// belief that two mentions of it agree.
    func computedPropertyName(containing node: Syntax) -> String? {
        var child = node
        var current = node.parent
        while let syntax = current {
            if syntax.is(ClosureExprSyntax.self)
                || syntax.is(FunctionDeclSyntax.self)
                || syntax.is(InitializerDeclSyntax.self)
                || syntax.is(SubscriptDeclSyntax.self) { return nil }

            // Reached on the way up out of the explicit form. A `set`,
            // `willSet` or `didSet` body runs on write, not on read, so it is
            // not a fresh read per access and keeps the ordinary message.
            if let accessor = syntax.as(AccessorDeclSyntax.self) {
                guard accessor.accessorSpecifier.tokenKind == .keyword(.get) else { return nil }
            }
            if let accessors = syntax.as(AccessorBlockSyntax.self) {
                guard isSingleExpressionGetter(accessors),
                      let binding = accessors.parent?.as(PatternBindingSyntax.self),
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                else { return nil }
                return name
            }
            child = syntax
            current = syntax.parent
        }
        return nil
    }

    /// True when `accessors` is a getter of exactly one statement.
    ///
    /// Both spellings again: `{ Date() }` carries the item list directly, and
    /// `{ get { Date() } }` carries it in the `get` accessor's body. A getter
    /// that reached its value in several steps has already bound it to a name,
    /// and binding it is the fix.
    private func isSingleExpressionGetter(_ accessors: AccessorBlockSyntax) -> Bool {
        switch accessors.accessors {
        case .getter(let items):
            return items.count == 1

        case .accessors(let list):
            guard let getter = list.first(where: {
                $0.accessorSpecifier.tokenKind == .keyword(.get)
            }) else { return false }
            return getter.body?.statements.count == 1
        }
    }

    /// True when `node` sits in a function/initializer parameter's default
    /// value — `init(id: UUID = UUID())` is the injection seam, not inline
    /// nondeterminism.
    ///
    /// ## A closure default is a seam too
    ///
    /// This used to stop at any `ClosureExprSyntax`, so
    /// `clock: () -> Date = { Date() }` was reported — the exact shape this
    /// rule's own documentation offers as the fix, and the shape a reader who
    /// takes its advice ends up writing. The corpus said so plainly: three
    /// sites across two repositories carried a hand-written
    /// `swiftprojectlint:disable:next` for this rule, each with a comment
    /// saying the same thing — *"the seam itself... that is what a default is
    /// for."* Nobody traced the suppressions back here.
    ///
    /// A default value is substitutable by construction, and it makes no
    /// difference whether the value handed over is the instant (`= Date()`) or
    /// the capability that reads it (`= { Date() }`). A test passes
    /// `{ fixedDate }` to either. The closure is not invoked at the seam; it is
    /// the production implementation of one.
    ///
    /// The distinction that is *not* generalised: a closure argument at a
    /// call site. `items.map { Date() }` runs immediately and
    /// `queue.async { stamp = Date() }` runs later with nothing able to replace
    /// it, so the substitutability has to come from the parameter, which is why
    /// this stays keyed on `defaultValue` rather than on being a closure.
    ///
    /// The walk requires the node to sit *inside* the parameter's default-value
    /// clause rather than merely to have a parameter ancestor, and a function
    /// or accessor body between the two ends it — a nested declaration's body
    /// is code that runs, not a value being handed over.
    /// Whether the read is **handed straight on** — its value becomes a call argument and this
    /// scope never looks at it.
    ///
    /// This is the shape the rest of this rule's own advice produces. "Move the clock read to the
    /// edge and pass the instant down" is what the ordinary message asks for, and a reader who does
    /// it lands here: `resolve(asOf: Date())`, `store.approve(on: Date())`,
    /// `EvalReport(startedAt: Date(), …)`. The finding is still true — nothing can pin *this line* —
    /// but the sentence attached to it was not: everything that decides takes the instant as a
    /// parameter, so a test pins the decision at the callee's boundary. Telling a reader their code
    /// is untestable when the untestable part is a single unexamined expression is how a rule talks
    /// someone out of a repair it asked for.
    ///
    /// **Argument position only, and that restriction is the whole precision.** A receiver is not
    /// handing the value on, it is *using* it: `Date().addingTimeInterval(timeout)` is a deadline,
    /// `Date().timeIntervalSince(start)` is an elapsed time, `Date.now.timeIntervalSince1970` is a
    /// number this scope computed. Every real defect this rule has produced across the corpus —
    /// the subprocess timeout, the benchmark timings, the rate limiters, the snapshot collision
    /// loop — reads the clock into a receiver or an operand, never into a bare argument.
    ///
    /// **The bound spelling counts too, and it had to.** `let now = Date()` at the top of a `body`,
    /// then `header(asOf: now)` and `content(asOf: now)`, is the archetype — it is the shape the
    /// repositories worked on earlier runs were left in, and an arm that could not label it would
    /// miss the case it exists for. Measured before shipping: the inline form alone reached 20 of
    /// 37 findings and the bound form takes it to 25, and every one of the five it adds carries a
    /// hand-written comment above it recording the defect that moving the read there fixed.
    ///
    /// The bound form demands that **every** reference to the binding is itself handed straight on.
    /// One comparison, one piece of arithmetic, one `return`, and the binding fails — which is the
    /// safe direction: a shadowed name can only add a reference that must also pass, never excuse
    /// one that does not. It is scoped to a local `let`; a stored property's initial value is not a
    /// composition root, because the read happens once per instance and the uses are elsewhere.
    func isHandedStraightOn(_ node: Syntax) -> Bool {
        // Reach through any member chain that only restates the value, so both spellings below ask
        // about the same expression: `bind(Date.now.timeIntervalSince1970, …)` is the argument form
        // and `let stamp = Date.now.formatted(…)` is the bound one.
        let effective = outermostRepresentation(of: node)
        if isArgumentPosition(effective) { return true }
        return isBoundAndOnlyPassedOn(effective)
    }

    /// `node` with every re-presenting member applied — the outermost expression that is still only
    /// the same fact in another type. Returns `node` itself when the first member does something.
    private func outermostRepresentation(of node: Syntax) -> Syntax {
        var outer = node
        while let member = outer.parent?.as(MemberAccessExprSyntax.self),
              member.base.map({ Syntax($0).id == outer.id }) == true,
              let next = representation(of: member) {
            outer = next
        }
        return outer
    }

    /// The `let name = <read>` case: a local binding whose every use is an argument.
    private func isBoundAndOnlyPassedOn(_ node: Syntax) -> Bool {
        guard let clause = node.parent?.as(InitializerClauseSyntax.self),
              Syntax(clause.value).id == node.id,
              let binding = clause.parent?.as(PatternBindingSyntax.self),
              let declaration = binding.parent?.parent?.as(VariableDeclSyntax.self),
              declaration.bindingSpecifier.text == "let",
              // A stored property is not a composition root: the read happens per instance and
              // the uses are in other members, where this walk cannot see them.
              declaration.parent?.parent?.is(CodeBlockItemListSyntax.self) == true,
              let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
              let scope = enclosingScope(of: Syntax(declaration)) else { return false }

        var references = 0
        var allPassedOn = true
        walkReferences(named: name, in: scope) { reference in
            references += 1
            if !self.isArgumentPosition(reference) { allPassedOn = false }
        }
        return references > 0 && allPassedOn
    }

    /// The nearest enclosing block, which is as far as a local binding can be seen.
    private func enclosingScope(of node: Syntax) -> Syntax? {
        var current = node.parent
        while let syntax = current {
            if syntax.is(CodeBlockSyntax.self) || syntax.is(AccessorBlockSyntax.self) {
                return syntax
            }
            current = syntax.parent
        }
        return nil
    }

    private func walkReferences(named name: String, in scope: Syntax, _ visit: (Syntax) -> Void) {
        for child in scope.children(viewMode: .sourceAccurate) {
            if let reference = child.as(DeclReferenceExprSyntax.self),
               reference.baseName.text == name {
                visit(Syntax(reference))
            }
            walkReferences(named: name, in: child, visit)
        }
    }

    private func isArgumentPosition(_ node: Syntax) -> Bool {
        var child = node
        var current = node.parent
        while let syntax = current {
            // A receiver, not an argument: this scope is about to do something with the value.
            // Re-presenting members were already stepped past by `outermostRepresentation(of:)`, so
            // anything still in receiver position here is combining.
            if let member = syntax.as(MemberAccessExprSyntax.self) {
                return member.base.map { Syntax($0).id == child.id } == false
            }
            if let element = syntax.as(LabeledExprSyntax.self),
               let list = element.parent?.as(LabeledExprListSyntax.self),
               let call = list.parent?.as(FunctionCallExprSyntax.self) {
                // The callee itself is not an argument.
                return Syntax(call.calledExpression).id != child.id
            }
            if syntax.is(CodeBlockSyntax.self) || syntax.is(AccessorBlockSyntax.self) { return false }
            guard isTransparentPassthrough(syntax) else { return false }
            child = syntax
            current = syntax.parent
        }
        return false
    }

    /// The outermost expression of a **re-presenting** member access, or `nil` when the member is
    /// doing something with the value rather than restating it.
    ///
    /// A receiver is normally where this rule's precision comes from: every defect it has produced
    /// across the corpus reads the clock into one. But four of the nine sites the composition-root
    /// arm could not reach were receivers that merely change the value's *type* and then hand it on:
    ///
    /// ```swift
    /// let stamp = Date.now.formatted(date: .abbreviated, time: .shortened)  // …timestamp: stamp
    /// statement.bind(Date.now.timeIntervalSince1970, at: 1)
    /// UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    /// ```
    ///
    /// None of those is a decision. The instant or the identity is the same fact in a `String` or a
    /// `Double`, handed to something that takes it as a parameter — which is the shape this arm
    /// exists to name.
    ///
    /// **The distinction is whether the member's arguments reach into the scope.** Combining the
    /// value with a local or a parameter produces a *new* fact, and that is where every defect lives:
    ///
    /// | expression | arguments | what it is |
    /// | --- | --- | --- |
    /// | `.uuidString` | none | the same identity as text |
    /// | `.timeIntervalSince1970` | none | the same instant as a number |
    /// | `.formatted(date: .abbreviated, time: .shortened)` | leading-dot style options | the same instant, formatted |
    /// | `.addingTimeInterval(timeout)` | **`timeout`** | a deadline |
    /// | `.timeIntervalSince(start)` | **`start`** | an elapsed time — a benchmark's whole output |
    ///
    /// Deliberately strict about what counts as inert: an argument may contain literals and
    /// leading-dot members and **nothing else**. One bare identifier and the member is treated as
    /// combining, because resolving whether that identifier is a local, a parameter or a static
    /// constant is a scope walk, and guessing it wrong turns a deadline into an end state.
    private func representation(of member: MemberAccessExprSyntax) -> Syntax? {
        guard let call = member.parent?.as(FunctionCallExprSyntax.self),
              Syntax(call.calledExpression).id == Syntax(member).id else {
            // A bare member with no call: `.uuidString`, `.timeIntervalSince1970`. Nothing was
            // supplied, so nothing was combined.
            return Syntax(member)
        }
        guard call.arguments.allSatisfy({ Self.isInert($0.expression) }),
              call.trailingClosure == nil,
              call.additionalTrailingClosures.isEmpty else { return nil }
        return Syntax(call)
    }

    /// An argument that supplies no value from the surrounding scope.
    ///
    /// The leading-dot test is written out rather than as
    /// `expression.as(MemberAccessExprSyntax.self)?.base == nil`, which reads correctly and is
    /// wrong: optional-chaining a non-member expression yields `nil`, and `nil == nil` is `true`, so
    /// that spelling calls **every** argument inert. It shipped for one build and the negative test
    /// for `Date().addingTimeInterval(timeout)` caught it — a deadline reported as an end state,
    /// which is the one direction this arm must never fail in.
    private static func isInert(_ expression: ExprSyntax) -> Bool {
        if let member = expression.as(MemberAccessExprSyntax.self), member.base == nil { return true }
        return !expression.tokens(viewMode: .sourceAccurate).contains { token in
            if case .identifier = token.tokenKind { return true }
            return false
        }
    }

    /// Wrappers that do not change what is being done with the value.
    ///
    /// Narrower than the `??`-chain walk's `isTransparentWrapper`, which also steps through tuple
    /// elements: a tuple *is* a value this scope built, so stepping through one would read
    /// `f((Date(), x))` as handing the instant on when what was handed on is the pair.
    private func isTransparentPassthrough(_ syntax: Syntax) -> Bool {
        syntax.is(TryExprSyntax.self) || syntax.is(AwaitExprSyntax.self)
    }

    func isParameterDefaultValue(_ node: Syntax) -> Bool {
        var child = node
        var current = node.parent
        while let syntax = current {
            if syntax.is(CodeBlockSyntax.self) || syntax.is(AccessorBlockSyntax.self) {
                return false
            }
            if let parameter = syntax.as(FunctionParameterSyntax.self) {
                guard let defaultValue = parameter.defaultValue else { return false }
                return Syntax(defaultValue).id == child.id
            }
            child = syntax
            current = syntax.parent
        }
        return false
    }
}

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

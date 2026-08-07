import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// The effect nobody can assert on.
///
/// `pureClosureCandidate` opens with the right argument — *an inline closure cannot be tested; there
/// is no name to call and no seam to reach it through* — and then narrows to **pure** closures,
/// refuting anything that writes to what it captured. For a property-test seed that refutal is
/// correct: you cannot generate inputs for a closure whose job is a side effect.
///
/// But the unreachability claim never depended on purity. It is scoped to the wrong conclusion: it
/// should refuse *property-test candidacy*, not refuse *extraction*. This rule is the other half —
/// a closure that **writes to captured state**, is **registered as a callback** rather than called
/// inline, and therefore has no seam through which any test can observe its effect. For effectful
/// closures the argument is stronger, not weaker: a silent regression in a side effect on shared
/// state is exactly what a test exists to catch.
///
///     .onKeyPress(.escape) {
///         viewport.selectedNodeId = nil
///         return .handled
///     }
///
/// Nothing can reach that. `ImageRenderer` drives a real draw pass but never fires key presses, and
/// ViewInspector cannot traverse a view whose body is a `GeometryReader`. Give the body a name and
/// "escape clears the selection" becomes a sentence a test can state.
///
/// **The suggestion is deliberately not `pureClosureCandidate`'s.** That rule says *its captures
/// become parameters*, which is wrong here — the mutation target stays captured. What changes is
/// that the *effect* acquires a name a test can invoke.
///
/// `info` severity. Reports a refactor, not a defect: the code works, it is simply unobservable.
final class UnreachableEffectClosureVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false
    private let purityInferrer = PurityInferrer()

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture,
              let surface = CallbackSurface(call: node),
              let closure = surface.callbackClosure(in: node),
              isWorthExtracting(closure),
              purityInferrer.mutatesCapturedState(closure) else {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: "The closure registered on `\(surface.name)` writes to captured state — "
                + "no test can reach its effect.",
            filePath: getFilePath(for: Syntax(closure)),
            lineNumber: getLineNumber(for: Syntax(closure)),
            suggestion: "Lift the body into a named method; the effect becomes assertable through "
                + "the state it writes.",
            ruleName: .unreachableEffectClosure,
            symbol: enclosingDeclarationName(of: node) ?? surface.name
        )
        return .visitChildren
    }

    /// Condition 3 — the body is more than a single call, so there is something to name.
    ///
    /// **This is what makes the rule converge**, and it is not a nicety. `.onKeyPress(.escape) {
    /// clearSelection() }` is the *fixed* form: reporting it would mean the rule fires forever on
    /// code that has already taken its advice, and a rule that cannot be satisfied gets switched
    /// off. A body that is exactly one `FunctionCallExprSyntax` — optionally `return`ed — is already
    /// a named seam, and an empty body has nothing to extract.
    ///
    /// A single *assignment* is not a call and does report. That is deliberate: `{ selectedId = nil
    /// }` has no name either, and naming it is exactly the fix. The asymmetry with `{ clear() }` is
    /// the point rather than an oversight — one has a seam, the other does not.
    private func isWorthExtracting(_ closure: ClosureExprSyntax) -> Bool {
        let statements = closure.statements
        guard let only = statements.first, statements.count == 1 else {
            return !statements.isEmpty
        }
        return !isSingleCall(only)
    }

    /// A statement that is exactly one call expression, with or without `return`.
    private func isSingleCall(_ statement: CodeBlockItemSyntax) -> Bool {
        let expression: ExprSyntax?
        switch statement.item {
        case .expr(let expr):
            expression = expr

        case .stmt(let stmt):
            expression = stmt.as(ReturnStmtSyntax.self)?.expression

        case .decl:
            expression = nil
        }
        return expression?.is(FunctionCallExprSyntax.self) ?? false
    }

    /// The declaration the closure is registered inside — the view's `body`, usually.
    ///
    /// A location rather than a subject, on the same terms `pureClosureCandidate` uses: the finding
    /// *is* a closure, so by definition it has no name of its own. `onTapGesture` names the
    /// operation, not the code, and every tap handler in a project would share it.
    private func enclosingDeclarationName(of node: some SyntaxProtocol) -> String? {
        var parent = node.parent
        while let current = parent {
            if let function = current.as(FunctionDeclSyntax.self) {
                return function.name.text
            }
            if let variable = current.as(VariableDeclSyntax.self),
               variable.parent?.is(MemberBlockItemSyntax.self) ?? false {
                return variable.bindings
                    .lazy
                    .compactMap { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text }
                    .first
            }
            parent = current.parent
        }
        return nil
    }
}

/// Where a callback closure is registered — condition 1, as two shapes rather than one.
///
/// Deliberately an allowlist rather than "any trailing closure on a member access in a view body".
/// That inference would sweep in `Toggle`, `ForEach` and every custom `@ViewBuilder`, none of which
/// register a callback. **Prefer under-reporting**: an unlisted modifier is a missed finding, while
/// a wrong inference is a finding the reader has to argue with. The cost is that the list drifts
/// behind SwiftUI, which is the maintenance this rule signs up for.
enum CallbackSurface {

    /// A view modifier — `.onTapGesture { … }`. A `MemberAccessExprSyntax` call.
    case modifier(String)

    /// A `Button`'s action. A `DeclReferenceExprSyntax` call, so the modifier match cannot see it,
    /// and it needs its own arm.
    ///
    /// In scope despite `buttonClosureWrapping` also looking at `Button`: that rule fires only on a
    /// body that is a *single no-argument call*, which is exactly the shape `isWorthExtracting`
    /// already excludes. The two cannot collide. Leaving `Button` out would have waived every
    /// multi-statement action — `Button { count += 1; save() }` — with nothing else reporting it.
    case buttonAction

    /// The SwiftUI callback surface, as an explicit list.
    ///
    /// `onAppear` / `onDisappear` are **deliberately absent**. `impureCallInViewBody`'s own
    /// suggestion is *"move it out of `body` — an action / `onAppear` for effects"*, so listing
    /// `onAppear` here would hand a reader straight from that rule's fix into this rule's finding.
    /// Two rules passing someone back and forth is how a whole category gets disabled. They are also
    /// usually one-liners, which condition 3 mostly refutes anyway, so the exclusion costs little.
    private static let modifiers: Set<String> = [
        "onTapGesture", "onLongPressGesture", "onKeyPress", "onContinuousHover", "onHover",
        "onChange", "onSubmit", "onDrag", "onDrop",
        // Gesture callbacks.
        "onEnded", "onChanged", "updating"
    ]

    init?(call: FunctionCallExprSyntax) {
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           Self.modifiers.contains(member.declName.baseName.text) {
            self = .modifier(member.declName.baseName.text)
            return
        }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self),
           reference.baseName.text == "Button" {
            self = .buttonAction
            return
        }
        return nil
    }

    var name: String {
        switch self {
        case .modifier(let name):
            return name

        case .buttonAction:
            return "Button"
        }
    }

    /// The closure that actually runs on the callback.
    ///
    /// For a modifier that is the trailing closure, or the first closure argument when it is written
    /// in parenthesised form.
    ///
    /// `Button` needs more care, because which closure is the *action* depends on the spelling. In
    /// `Button(action: { … }) { Text("Go") }` the trailing closure is the **label** — a
    /// `@ViewBuilder`, not a callback — and reporting it would be a false finding. So an explicit
    /// `action:` argument wins whenever it is present; only otherwise is the first trailing closure
    /// the action, which covers `Button("Title") { … }` and `Button { … } label: { … }`.
    func callbackClosure(in call: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        switch self {
        case .modifier:
            return call.trailingClosure ?? Self.firstClosureArgument(of: call)

        case .buttonAction:
            return Self.argument(labelled: "action", of: call) ?? call.trailingClosure
        }
    }

    private static func firstClosureArgument(of call: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        call.arguments.lazy
            .compactMap { $0.expression.as(ClosureExprSyntax.self) }
            .first
    }

    private static func argument(
        labelled label: String,
        of call: FunctionCallExprSyntax
    ) -> ClosureExprSyntax? {
        call.arguments.lazy
            .filter { $0.label?.text == label }
            .compactMap { $0.expression.as(ClosureExprSyntax.self) }
            .first
    }
}

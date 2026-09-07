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

    /// Per type, the names of its `@State` and `@FocusState` properties. See `writesOnlyViewState`.
    private var viewLocalState: [String: Set<String>] = [:]

    /// The nominal types currently being visited, innermost last.
    private var typeNameStack: [String] = []

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        let collector = ViewLocalStateCollector(viewMode: .sourceAccurate)
        collector.walk(node)
        viewLocalState = collector.byType
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture,
              let surface = CallbackSurface(call: node),
              let closure = surface.callbackClosure(in: node),
              isWorthExtracting(closure),
              purityInferrer.mutatesCapturedState(closure),
              !writesOnlyViewState(closure),
              !isBareStoreThroughASetter(closure) else {
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

    /// Condition 4 — the effect has somewhere to be observed from.
    ///
    /// The rule's promise is a testability one, in its own description: *"no test can reach its
    /// effect … naming it gives the effect one."* For a write to the enclosing view's own `@State`
    /// that promise is false, and `Tests/AppTests/StateSeamHarnessTests.swift` is the measurement
    /// rather than the argument.
    ///
    /// `@State`'s storage is allocated when SwiftUI installs the view. Before that the setter has
    /// nowhere to write and the getter answers from the initial value, so calling the extracted
    /// method leaves the property unchanged — and so does firing the button through ViewInspector,
    /// which the harness checks as its control because without it the result is only "nothing
    /// works". The one route that does observe the state is `ViewHosting.host`, and it goes through
    /// SwiftUI's storage rather than through the name, so it works identically for the inline body
    /// and the extracted method. **The seam a test uses is the button, and the button exists in
    /// both forms.**
    ///
    /// Deliberately narrow, because the harness also shows where the promise holds:
    ///
    /// - `@Binding` — the storage belongs to the parent, and a test supplies its own
    ///   `Binding(get:set:)` and reads the write back. Fifteen corpus write targets. Reported.
    /// - `@AppStorage` — the setter writes straight through to the defaults store, which a test
    ///   reads with no view at all. Four corpus write targets. Reported.
    /// - A member write (`viewModel.query = ""`, `items.append(x)`) — the object outlives the
    ///   view, so the method can move onto it and be called directly. Reported.
    ///
    /// So a single non-`@State` write anywhere in the body keeps the finding: the gate needs
    /// *every* write to be a direct assignment to view-local storage.
    ///
    /// `@FocusState` is included on measurement, not on mechanism — no corpus finding writes one,
    /// and the harness covers it anyway because that was cheaper than arguing about it.
    private func writesOnlyViewState(_ closure: ClosureExprSyntax) -> Bool {
        guard let enclosing = typeNameStack.last,
              let stateNames = viewLocalState[enclosing] else { return false }
        let collector = ClosureWriteTargetCollector(viewMode: .sourceAccurate)
        collector.walk(closure.statements)
        guard !collector.directWrites.isEmpty, collector.otherWrites.isEmpty else { return false }
        return collector.directWrites.isSubset(of: stateNames)
    }

    /// Condition 5 — a single store through a setter is already a named seam.
    ///
    /// Condition 3 exempts a body that is exactly one *call*, because a call is a name a test can
    /// reach. A member assignment is a call to a named setter, and unlike view-local `@State` the
    /// property it writes is readable — so `Button { viewModel.sortOption = option }` writes state
    /// a test asserts on today, with no extraction at all. `StateSeamHarnessTests` records that as
    /// three lines, because the claim is that small.
    ///
    /// The doc's defended asymmetry — *"a single assignment is not a call and does report"* — was
    /// right about `{ selectedId = nil }` on view-local state, where there genuinely is no seam,
    /// and it generalised one step too far. Condition 4 removed that case for a different reason;
    /// this removes the case where the seam already exists.
    ///
    /// **The right-hand side has to be a value the caller already has.** A call on the right is
    /// computation the closure owns and nothing else can reach —
    /// `viewport.hoveredNodeId = hitNode(at: location)?.id` is the rule's own motivating shape, and
    /// it keeps reporting. So does anything with more than one statement: two writes that must
    /// happen together are a contract worth naming, which one write is not.
    private func isBareStoreThroughASetter(_ closure: ClosureExprSyntax) -> Bool {
        let statements = closure.statements
        guard statements.count == 1, let only = statements.first,
              case .expr(let expression) = only.item,
              let sequence = expression.as(SequenceExprSyntax.self) else { return false }
        let elements = Array(sequence.elements)
        guard elements.count == 3, elements[1].is(AssignmentExprSyntax.self),
              elements[0].is(MemberAccessExprSyntax.self) else { return false }
        return !Self.containsCall(elements[2])
    }

    /// Whether an expression computes anything, as opposed to naming a value that already exists.
    private static func containsCall(_ expression: ExprSyntax) -> Bool {
        CallFinder(viewMode: .sourceAccurate).foundCall(in: Syntax(expression))
    }

    // MARK: - Enclosing-type tracking

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) { typeNameStack.removeLast() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) { typeNameStack.removeLast() }

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

/// Per type, the `@State` and `@FocusState` property names a file declares.
///
/// Keyed by type rather than gathered per file: two views in one file routinely use the same
/// property name for different storage, and a file-wide set would let one view's `@State private
/// var text` gate another view's `@Binding var text`.
private final class ViewLocalStateCollector: SyntaxVisitor {

    private(set) var byType: [String: Set<String>] = [:]

    private static let viewLocalWrappers: Set<String> = ["State", "FocusState"]

    private var typeNameStack: [String] = []

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) { typeNameStack.removeLast() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) { typeNameStack.removeLast() }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let type = typeNameStack.last else { return .visitChildren }
        let wrapped = node.attributes.contains { attribute in
            guard let name = attribute.as(AttributeSyntax.self)?
                .attributeName.as(IdentifierTypeSyntax.self)?.name.text else { return false }
            return Self.viewLocalWrappers.contains(name)
        }
        guard wrapped else { return .visitChildren }
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                byType[type, default: []].insert(identifier.identifier.text)
            }
        }
        return .visitChildren
    }
}

/// What a closure body writes to, split by whether the write lands in view-local storage.
///
/// `directWrites` are bare-identifier assignments and `toggle()` — the shapes that reach a
/// `@State` property itself. `otherWrites` is everything else that mutates: a member assignment
/// (`viewModel.error = nil`), or a mutating call on a receiver (`items.append(x)`). One entry in
/// `otherWrites` disqualifies the whole closure, because the gate's claim is about the *only*
/// thing the body does.
private final class ClosureWriteTargetCollector: SyntaxVisitor {

    private(set) var directWrites: Set<String> = []
    private(set) var otherWrites: Set<String> = []

    /// Calls that mutate their receiver. An allowlist, for the reason `CallbackSurface` gives:
    /// an unlisted name is a missed disqualification and so a kept finding, which is the safe
    /// direction, while a wrong inference gates something real.
    private static let mutatingCalls: Set<String> = [
        "append", "insert", "remove", "removeAll", "removeFirst", "removeLast", "removeValue",
        "sort", "reverse", "popLast", "formUnion", "subtract"
    ]

    /// Assignment is read off `SequenceExprSyntax`, not `InfixOperatorExprSyntax`: an unfolded
    /// tree — what `Parser.parse` produces and what every visitor here walks — represents
    /// `flag = true` as a three-element sequence. `InfixOperatorExprSyntax` appears only after
    /// operator folding, which the linter never does.
    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let elements = Array(node.elements)
        guard elements.count >= 2, Self.isAssignment(elements[1]) else { return .visitChildren }
        record(target: elements[0])
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              let receiver = member.base?.as(DeclReferenceExprSyntax.self) else {
            return .visitChildren
        }
        let name = member.declName.baseName.text
        if name == "toggle" {
            directWrites.insert(receiver.baseName.text)
        } else if Self.mutatingCalls.contains(name) {
            otherWrites.insert(receiver.baseName.text)
        }
        return .visitChildren
    }

    private func record(target: ExprSyntax) {
        if let reference = target.as(DeclReferenceExprSyntax.self) {
            directWrites.insert(reference.baseName.text)
            return
        }
        if let member = target.as(MemberAccessExprSyntax.self) {
            otherWrites.insert(member.description.trimmingCharacters(in: .whitespaces))
            return
        }
        // A subscript, a tuple destructuring, anything else — treat as a write that is not a
        // plain `@State` assignment rather than ignoring it.
        otherWrites.insert(target.description.trimmingCharacters(in: .whitespaces))
    }

    /// `=` is an `AssignmentExprSyntax`; `+=` and friends are binary operators whose text ends
    /// in `=` without being a comparison.
    private static func isAssignment(_ element: ExprSyntax) -> Bool {
        if element.is(AssignmentExprSyntax.self) { return true }
        guard let binary = element.as(BinaryOperatorExprSyntax.self) else { return false }
        let text = binary.operator.text
        return text.hasSuffix("=") && !["==", "!=", "<=", ">=", "==="].contains(text)
    }
}

/// Whether a subtree contains a call — the test condition 5 uses for "the closure computes
/// something the caller cannot already reach".
private final class CallFinder: SyntaxVisitor {

    private var found = false

    func foundCall(in node: Syntax) -> Bool {
        found = false
        walk(node)
        return found
    }

    override func visit(_ _: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        found = true
        return .skipChildren
    }
}

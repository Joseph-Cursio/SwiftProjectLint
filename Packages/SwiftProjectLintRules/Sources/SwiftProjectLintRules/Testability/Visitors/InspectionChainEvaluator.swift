import SwiftSyntax

/// Reads a member-access chain from its root, step by step, the way ViewInspector resolves it.
///
/// A chain is only read when its root is an inspected view: `.inspect()`, a relay-closure
/// parameter, `self` inside `extension InspectableView`, or a local bound to one of those. Every
/// name match happens after that, so `label.text` on a `UILabel` never gets this far. One
/// evaluator serves one file.
final class InspectionChainEvaluator {

    /// View types declared in the file being read. A test inspecting one of them walks a layout it
    /// declared itself — ViewInspector compatibility probes do exactly this. Also the test's own
    /// finder helpers, declared in `extension InspectableView`.
    let declaredViews: DeclaredViews
    let resolver = InspectionBindingResolver()

    /// Bounds a pathological chain of links and bindings.
    static let maxDepth = 64

    init(declaredViews: DeclaredViews) {
        self.declaredViews = declaredViews
    }

    func evaluate(_ expr: ExprSyntax) -> ChainEvaluation {
        evaluate(expr, depth: 0)
    }

    private func evaluate(_ expr: ExprSyntax, depth: Int) -> ChainEvaluation {
        guard depth < Self.maxDepth else { return .unrelated }
        let expr = Self.unwrapped(expr)
        if let call = expr.as(FunctionCallExprSyntax.self) {
            return evaluateCall(call, depth: depth)
        }
        if let subscriptCall = expr.as(SubscriptCallExprSyntax.self) {
            return evaluateSubscript(subscriptCall, depth: depth)
        }
        if let member = expr.as(MemberAccessExprSyntax.self), let base = member.base {
            return evaluateProperty(member, of: base, depth: depth)
        }
        if let reference = expr.as(DeclReferenceExprSyntax.self) {
            return ChainEvaluation(state: state(of: reference, depth: depth))
        }
        return .unrelated
    }

    // MARK: - Calls

    private func evaluateCall(_ call: FunctionCallExprSyntax, depth: Int) -> ChainEvaluation {
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self), let base = member.base {
            let name = member.declName.baseName.text
            let receiver = evaluate(base, depth: depth + 1)
            if name == "inspect" {
                // `actualView().inspect()` starts over, but what came before is still in this chain.
                guard InspectionVocabulary.isRootInspect(call) else { return receiver.ended }
                return receiver.ended.then(ChainEvaluation(state: rootState(of: call, inspecting: base, depth: depth)))
            }
            guard let state = receiver.state else { return receiver }
            return receiver.then(step(name, call: call, node: Syntax(member.declName)).apply(to: state))
        }
        guard let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) else { return .unrelated }
        let name = reference.baseName.text
        if let root = Self.inspectableExtensionRoot(of: Syntax(call), ownership: declaredViews.ownership(of:)) {
            return step(name, call: call, node: Syntax(reference)).apply(to: root)
        }
        if name == "inspect", InspectionVocabulary.isRootInspect(call) {
            // A view's own extension calling `inspect()` on itself.
            return ChainEvaluation(state: .root(.root, ownership: .app))
        }
        return .unrelated
    }

    private func step(_ name: String, call: FunctionCallExprSyntax, node: Syntax) -> InspectionStep {
        InspectionStep(name: name, call: call, node: node, declaredViews: declaredViews, resolver: resolver)
    }

    /// `inspect()` on an app view is a root; on a modifier it is `ViewModifier<Self>`, whose
    /// children are the views `body(content:)` builds. On a style, or on a SwiftUI view built in the
    /// test, it is the view itself.
    private func rootState(
        of call: FunctionCallExprSyntax,
        inspecting subject: ExprSyntax,
        depth: Int
    ) -> InspectionChainState {
        let typeName = subjectType(of: subject, depth: depth)
        let kind: ReceiverKind
        if InspectionVocabulary.isStyleInspect(call) || typeName?.hasSuffix("Style") == true
            || typeName.map(InspectionVocabulary.isSwiftUIViewType) == true {
            kind = .found
        } else {
            kind = typeName?.hasSuffix("Modifier") == true ? .content : .root
        }
        return .root(kind, ownership: declaredViews.ownership(of: typeName))
    }

    private func evaluateSubscript(_ subscriptCall: SubscriptCallExprSyntax, depth: Int) -> ChainEvaluation {
        let receiver = evaluate(subscriptCall.calledExpression, depth: depth + 1)
        guard let state = receiver.state else { return receiver }
        let index = subscriptCall.arguments.trimmedDescription
        let step = PositionalStep(kind: .matchIndex("[\(index)]"), node: Syntax(subscriptCall.leftSquare))
        let key = subscriptCall.arguments.first?.expression
        if state.isMatchList {
            // `[0]` is `.first`, the match an unpredicated `find` returns. The order of the matches
            // is the receiver's layout, so the receiver's ownership decides.
            guard index != "0", key.map(isLoopOverEveryPosition) != true, state.isArgumentList == false else {
                return receiver.then(ChainEvaluation(state: state.element))
            }
            return receiver.then(.reporting(step, from: state, leaving: state.element))
        }
        // A toolbar's only child. On a custom view's body `[0]` is the first of its views, below.
        if state.kind == .singleChild, index == "0" {
            return receiver.then(InspectionStep.oneLevelDown(
                from: state, to: .found, ownership: state.ownership, step: "[0]", written: "[0]", node: step.node
            ))
        }
        if key.map(isLoopOverEveryPosition) == true {
            return receiver.then(ChainEvaluation(state: state.element))
        }
        let isOwnFirstChild = state.isItsOwnFirstChild && index == "0"
        guard InspectionVocabulary.isPositionalKey(subscriptCall.arguments, resolver: resolver),
              state.isDataReceiver == false,
              isOwnFirstChild == false else {
            return receiver.then(ChainEvaluation(state: isOwnFirstChild ? state : state.element))
        }
        let pick = PositionalStep(kind: .childIndex("[\(index)]"), node: step.node)
        return receiver.then(.reporting(pick, from: state, leaving: state.element))
    }

    /// `.first` on a list of matches is `find` by another name; `.last` is an ordinal. On a
    /// container — a custom view's body among them — both are children by position, except a
    /// `ForEach`'s rows and a found view, whose only child is itself, and a toolbar's only child.
    /// `self.x` reads a property. Any other property ends the chain.
    private func evaluateProperty(_ member: MemberAccessExprSyntax, of base: ExprSyntax, depth: Int) -> ChainEvaluation {
        let name = member.declName.baseName.text
        if Self.namesEnclosingType(Self.unwrapped(base), from: Syntax(member)) {
            let binding = resolver.resolveProperty(name, from: Syntax(member))
            return ChainEvaluation(state: binding.flatMap { state(of: $0, depth: depth) })
        }
        let receiver = evaluate(base, depth: depth + 1)
        guard let state = receiver.state, name == "first" || name == "last" else { return receiver.ended }
        let node = Syntax(member.declName)
        if state.isMatchList {
            guard name == "last", state.isArgumentList == false else {
                return receiver.then(ChainEvaluation(state: state.element))
            }
            let step = PositionalStep(kind: .matchIndex(".last"), node: node)
            return receiver.then(.reporting(step, from: state, leaving: state.element))
        }
        if state.isItsOwnFirstChild {
            return receiver.then(ChainEvaluation(state: state))
        }
        if state.kind == .singleChild, name == "first" {
            return receiver.then(InspectionStep.oneLevelDown(
                from: state, to: .found, ownership: state.ownership, step: ".first", written: ".first", node: node
            ))
        }
        guard state.isDataReceiver == false else { return receiver.then(ChainEvaluation(state: state.element)) }
        let step = PositionalStep(kind: .childIndex(".\(name)"), node: node)
        return receiver.then(.reporting(step, from: state, leaving: state.element))
    }

    // MARK: - Roots

    private func state(of reference: DeclReferenceExprSyntax, depth: Int) -> InspectionChainState? {
        let name = reference.baseName.text
        if name == "self" {
            return Self.inspectableExtensionRoot(of: Syntax(reference), ownership: declaredViews.ownership(of:))
        }
        // A capitalised name is a type — `ViewType`, `Color` — not a value worth resolving.
        guard name.first?.isUppercase == false else { return nil }
        return resolver.resolve(name, from: Syntax(reference)).flatMap { state(of: $0, depth: depth) }
    }

    private func state(of binding: InspectionBinding, depth: Int) -> InspectionChainState? {
        switch binding {
        case let .value(value, annotation):
            // The binding's own statement reports any positional step in it; only its state matters here.
            if let state = evaluate(value, depth: depth + 1).state { return state }
            let declared = annotation.map(InspectableViewType.init)
            return declared?.isInspectableView == true ? declared.map(state(declaredAs:)) : nil

        case .element(let sequence):
            return evaluate(sequence, depth: depth + 1).state?.element

        case .relayParameter(let subject):
            // ViewInspector hands the relay `View<Subject>`, whose children are the body's views.
            let typeName = subject.flatMap { subjectType(of: $0, depth: depth + 1) }
            return .root(.content, ownership: declaredViews.ownership(of: typeName))

        case .inspectableView(let declared):
            return state(declaredAs: declared)

        case .declared, .opaque:
            return nil
        }
    }

    private func state(declaredAs declared: InspectableViewType) -> InspectionChainState {
        let ownership = declaredViews.ownership(of: declared.subjectType)
        var state = InspectionChainState.root(declared.kind, ownership: ownership, after: declared.viewType)
        if declared.isArgumentList {
            // Each argument is a view of the declared type; `element` hands one back as it is.
            state.isMatchList = true
            state.matchesOwnership = ownership
            state.isArgumentList = true
        }
        return state
    }
}

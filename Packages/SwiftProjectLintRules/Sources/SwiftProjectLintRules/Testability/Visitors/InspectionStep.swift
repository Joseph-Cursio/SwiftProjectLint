import SwiftSyntax

/// One call in a chain on an inspected view, and what it does to the chain's state.
///
/// Whether an accessor moves depends on its receiver (see `ReceiverKind`). After
/// `find(viewWithAccessibilityIdentifier:)` the receiver is the found view itself, so `.text()`
/// only checks its type — the shape the rule recommends. After `inspect()` on an app view, `.vStack()`
/// reaches the body's root: one level. The first level below an anchor only asserts what the anchor
/// reached; the second has to walk.
struct InspectionStep {
    let name: String
    let call: FunctionCallExprSyntax
    let node: Syntax
    let declaredViews: DeclaredViews
    let resolver: InspectionBindingResolver

    func apply(to state: InspectionChainState) -> ChainEvaluation {
        if isFinderHelperCall {
            return .unrelated
        }
        if state.isMatchList {
            // `first(where:)` and `last(where:)` select by predicate.
            let search = (name == "first" || name == "last") && InspectionChainEvaluator.passesClosure(call)
            return ChainEvaluation(state: search ? state.element : nil)
        }
        switch name {
        case "find":
            return findStep(from: state)

        case "findAll":
            // The matches' order is the layout the search covers; each match is in its own type's.
            var matches = state.reanchored(searchedKind, ownership: state.ownership.searched, after: searchedAccessor)
            matches.isMatchList = true
            matches.matchesOwnership = searchOwnership(from: state)
            return ChainEvaluation(state: matches)

        case "parent":
            return parentStep(from: state)

        case "modifier":
            // `modifier(Card.self)` reaches a custom modifier by type; SwiftUI's takes an instance.
            guard metatypeName(call.arguments.first) != nil else { return .unrelated }
            let reached = state.reanchored(.content, ownership: stepOwnership(from: state), after: name)
            return ChainEvaluation(state: reached)

        default:
            break
        }
        return vocabularyStep(from: state)
    }

    /// `button(.increment)` where the file declares `func button(_ id: A11y)` in
    /// `extension InspectableView`: the test's own helper, which a search sits behind. The call has
    /// to fit the helper's parameters — `find(ViewType.HStack.self)` is not `find(_ id: String)`.
    /// Called with integer literals only, or with nothing, the name is still ViewInspector's.
    private var isFinderHelperCall: Bool {
        guard let helpers = declaredViews.finderHelpers[name], call.arguments.isEmpty == false,
              call.arguments.contains(where: { $0.expression.is(IntegerLiteralExprSyntax.self) == false }) else {
            return false
        }
        return helpers.contains { $0.accepts(call, resolver: resolver) }
    }

    private func vocabularyStep(from state: InspectionChainState) -> ChainEvaluation {
        if InspectionVocabulary.orderedSlots.contains(name) {
            return orderedSlotStep(from: state)
        }
        if InspectionVocabulary.transparentSteps.contains(name) {
            var same = state
            if name == "classified" { same.kind = .found }
            return ChainEvaluation(state: same)
        }
        if InspectionVocabulary.namedSlots.contains(name) {
            let kind: ReceiverKind
            if InspectionVocabulary.presentedContentSlots.contains(name) {
                kind = .content
            } else {
                kind = InspectionVocabulary.unwrappingSlots.contains(name) ? .singleChild : .slot
            }
            return ChainEvaluation(state: state.reanchored(kind, ownership: state.ownership, after: name))
        }
        if InspectionVocabulary.viewTypeAccessors.contains(name) {
            return accessorStep(from: state)
        }
        return .unrelated
    }

    // MARK: - Searches

    /// A search resets the walk. `skipFound: n` is the one form that still picks by order: the
    /// (n+1)th match, as `findAll(…)[n]` would — in the layout the search covers. Like that
    /// subscript, a loop's index over every position compares the matches in order instead.
    private func findStep(from state: InspectionChainState) -> ChainEvaluation {
        let next = state.reanchored(
            searchedKind, ownership: searchOwnership(from: state), after: searchedAccessor ?? name
        )
        guard let skip = call.arguments.first(where: { $0.label?.text == "skipFound" }),
              skip.expression.trimmedDescription != "0",
              LoopPositions.isLoopOverEveryPosition(skip.expression, resolver: resolver) == false else {
            return ChainEvaluation(state: next)
        }
        var searched = state
        searched.ownership = state.ownership.searched
        let step = PositionalStep(kind: .matchIndex("skipFound: \(skip.expression.trimmedDescription)"), node: node)
        return .reporting(step, from: searched, leaving: next)
    }

    /// What a search returns: `find(ViewType.X.self)` an `X`, `find(Row.self)` the custom view
    /// `Row` — whose children are its body's views — `find(text:)` a `Text`; every other form — an
    /// identifier, a predicate, a relation — the found view itself.
    private var searchedKind: ReceiverKind {
        if let typeName = metatypeName(call.arguments.first) {
            return InspectionVocabulary.isViewTypeName(typeName) ? .typed : .content
        }
        let labels = call.arguments.compactMap { $0.label?.text }
        return labels.contains(where: InspectionVocabulary.typedFindLabels.contains) ? .typed : .found
    }

    /// `parent()` never casts: it always climbs, and how far up the wanted view sits is layout. The
    /// climb leaves whatever the chain had reached, so the root's whole tree decides ownership.
    private func parentStep(from state: InspectionChainState) -> ChainEvaluation {
        guard call.arguments.isEmpty, InspectionChainEvaluator.passesClosure(call) == false else {
            return .unrelated
        }
        var climbed = state
        climbed.ownership = state.rootOwnership.searched
        let next = state.reanchored(.found, ownership: climbed.ownership, after: name)
        return .reporting(PositionalStep(kind: .parent, node: node), from: climbed, leaving: next)
    }

    /// `toolbar().item(2)` picks the third `ToolbarItem` as declared, and `item(0)` the first of
    /// however many there are. `item()` takes the first too, but cannot be told from a toolbar's
    /// only item, so it is not reported; like a named slot, it starts a new anchor, from which the
    /// item's own views are counted in order. ViewInspector's own tests read `toolbar().item().text()`.
    ///
    /// `navigationBarItems` never reaches the bar items: it takes one of the receiver's children,
    /// strips the wrapper `.navigationBarItems(…)` put around it, and returns the view the modifier
    /// was applied to. So it is not a slot of the receiver: on a container, `navigationBarItems(n)`
    /// reads child `n`, exactly as `vStack(n)` does, and without an index the child `x()` would.
    private func orderedSlotStep(from state: InspectionChainState) -> ChainEvaluation {
        let isBarItems = name == "navigationBarItems"
        let next = state.reanchored(isBarItems ? .slot : .typed, ownership: state.ownership, after: name)
        switch AccessorArguments(call, resolver: resolver) {
        case .noArguments, .metatype:
            return isBarItems ? barItemsOfOnlyChild(from: state) : ChainEvaluation(state: next)

        case .index(let index), .metatypeAndIndex(let index):
            if isBarItems, index == "0", state.hasOnlyChild {
                return barItemsOfOnlyChild(from: state)
            }
            let everyPosition = call.arguments.last.map {
                LoopPositions.isLoopOverEveryPosition($0.expression, resolver: resolver)
            } == true
            guard everyPosition == false else { return ChainEvaluation(state: next) }
            return .reporting(PositionalStep(kind: .indexed(written), node: node), from: state, leaving: next)

        case .other:
            return .unrelated
        }
    }

    /// `navigationBarItems()` — or `navigationBarItems(0)` where `x(0)` is `x()` — unwraps the
    /// receiver's only child. On a found view, a slot or a bare `inspect()` that child is the
    /// receiver itself — unlike `x()`, ViewInspector does not fall back to an app view's body here —
    /// so the step unwraps in place and starts a new anchor. Anywhere else the child is one level
    /// down, the first of a container's, and a second level since the anchor is a walk, as
    /// `navigationView().form()` is. It is not reported as a pick: the rule cannot count a
    /// container's children, and with one child the step only asserts which view the modifier was
    /// applied to.
    private func barItemsOfOnlyChild(from state: InspectionChainState) -> ChainEvaluation {
        guard state.castsInPlace == false, state.kind != .root else {
            return ChainEvaluation(state: state.reanchored(.slot, ownership: state.ownership, after: name))
        }
        return Self.oneLevelDown(
            from: state, to: .slot, ownership: state.ownership, step: name, written: written, node: node
        )
    }

    // MARK: - View-type accessors

    /// `x()` takes the receiver's only child; `x(n)` picks a sibling, and so does `x(0)` unless the
    /// receiver has only one child (`hasOnlyChild`). `view(T.self)` does the same as `x()` but
    /// leaves a custom view `T`, whose children are its body's views.
    private func accessorStep(from state: InspectionChainState) -> ChainEvaluation {
        let isView = name == "view"
        switch AccessorArguments(call, resolver: resolver) {
        case .noArguments where isView == false:
            return onlyChild(of: state, becoming: .typed)

        case .metatype where isView:
            return onlyChild(of: state, becoming: .content)

        case .index(let index) where isView == false:
            if index == "0", state.hasOnlyChild { return onlyChild(of: state, becoming: .typed) }
            return indexedStep(from: state, becoming: .typed)

        case .metatypeAndIndex(let index) where isView:
            if index == "0", state.hasOnlyChild { return onlyChild(of: state, becoming: .content) }
            return indexedStep(from: state, becoming: .content)

        default:
            return .unrelated
        }
    }

    /// On a found view or a slot the only child is the view itself, so the step is a cast; on a
    /// root, `view(MyView.self)` names the subject's own type. Anywhere else it goes one level down,
    /// and a second level since the anchor is a walk.
    private func onlyChild(of state: InspectionChainState, becoming kind: ReceiverKind) -> ChainEvaluation {
        let isCast = state.castsInPlace || (state.kind == .root && name == "view")
        if isCast {
            var cast = state
            cast.kind = kind
            cast.lastStep = name
            cast.ownership = stepOwnership(from: state)
            return ChainEvaluation(state: cast)
        }
        return Self.oneLevelDown(
            from: state, to: kind, ownership: stepOwnership(from: state), step: name, written: written, node: node
        )
    }

    /// One level below the receiver, reported when it is the second since the anchor. A step that
    /// crosses into another view's layout — `view(AppRow.self)` inside a test-declared host — is
    /// judged in the layout it leaves; the layout it enters is walked from its top, as
    /// `find(AppRow.self)` would reach it.
    static func oneLevelDown(
        from state: InspectionChainState,
        to kind: ReceiverKind,
        ownership: LayoutOwnership,
        step: String,
        written: String,
        node: Syntax
    ) -> ChainEvaluation {
        var next = state.advanced(by: step, to: kind, ownership: ownership)
        let walks = next.stepsSinceAnchor >= 2
        if next.ownership != state.ownership {
            next.stepsSinceAnchor = 0
        }
        guard walks else { return ChainEvaluation(state: next) }
        return .reporting(PositionalStep(kind: .descent(written), node: node), from: state, leaving: next)
    }

    /// One report per pick: the picked view becomes a new anchor. An index that a loop runs over
    /// every position compares the whole sequence instead.
    private func indexedStep(from state: InspectionChainState, becoming kind: ReceiverKind) -> ChainEvaluation {
        let index = call.arguments.last?.expression
        let everyPosition = index.map { LoopPositions.isLoopOverEveryPosition($0, resolver: resolver) }
        if state.isDataReceiver || everyPosition == true {
            // A `ForEach` row, or an action sheet's button: data, not layout.
            return ChainEvaluation(state: state.reanchored(kind, ownership: stepOwnership(from: state)))
        }
        let next = state.reanchored(kind, ownership: stepOwnership(from: state), after: name)
        return .reporting(PositionalStep(kind: .indexed(written), node: node), from: state, leaving: next)
    }

    // MARK: - Arguments

    /// Ownership follows the subject: `view(CounterView.self)` inside a test-declared host walks
    /// `CounterView`, which the test does not own. Any other step stays in the receiver's layout.
    private func stepOwnership(from state: InspectionChainState) -> LayoutOwnership {
        namedOwnership ?? state.ownership
    }

    /// A search names its subject, or may land anywhere below the receiver: inside a host that
    /// wraps an app view, that is the app's layout.
    private func searchOwnership(from state: InspectionChainState) -> LayoutOwnership {
        namedOwnership ?? state.ownership.searched
    }

    private var namedOwnership: LayoutOwnership? {
        guard let typeName = metatypeName(call.arguments.first),
              InspectionVocabulary.isViewTypeName(typeName) == false else {
            return nil
        }
        return declaredViews.ownership(of: InspectionVocabulary.typeName(typeName))
    }

    /// `find(ViewType.ForEach.self)` finds a `ForEach`, so an index after it is a row, as after
    /// `forEach()`. Spelled as the accessor the type would have: `ForEach` → `forEach`.
    private var searchedAccessor: String? {
        guard let typeName = metatypeName(call.arguments.first), InspectionVocabulary.isViewTypeName(typeName) else {
            return nil
        }
        return InspectionVocabulary.accessorName(forViewType: InspectionVocabulary.typeName(typeName))
    }

    private func metatypeName(_ argument: LabeledExprSyntax?) -> String? {
        Self.metatypeName(argument)
    }

    /// `ViewType.Text.self` → `ViewType.Text`, for an unlabelled metatype argument.
    static func metatypeName(_ argument: LabeledExprSyntax?) -> String? {
        guard let argument, argument.label == nil,
              let metatype = argument.expression.as(MemberAccessExprSyntax.self),
              metatype.declName.baseName.text == "self" else {
            return nil
        }
        return metatype.base?.trimmedDescription
    }

    /// `find(Row.self)` → `Row`: the custom view a search or cast names.
    static func customViewType(searchedBy call: FunctionCallExprSyntax) -> String? {
        guard let typeName = metatypeName(call.arguments.first),
              InspectionVocabulary.isViewTypeName(typeName) == false else {
            return nil
        }
        return InspectionVocabulary.typeName(typeName)
    }

    /// The step as written, on one line.
    private var written: String {
        let arguments = call.arguments.map { argument in
            let value = argument.expression.trimmedDescription
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return argument.label.map { "\($0.text): \(value)" } ?? value
        }
        return "\(name)(\(arguments.joined(separator: ", ")))"
    }
}

/// The argument shapes ViewInspector's accessors take. A SwiftUI modifier of the same name always
/// takes a value, a view or a closure instead.
private enum AccessorArguments {
    case noArguments
    case metatype
    case index(String)
    case metatypeAndIndex(String)
    case other

    init(_ call: FunctionCallExprSyntax, resolver: InspectionBindingResolver) {
        let arguments = Array(call.arguments)
        guard InspectionChainEvaluator.passesClosure(call) == false,
              arguments.allSatisfy({ $0.label == nil }) else {
            self = .other
            return
        }
        switch arguments.count {
        case 0:
            self = .noArguments

        case 1:
            let only = arguments[0].expression
            let sequenceMethod = Self.collidesWithSequence(call)
            if Self.isMetatype(only) {
                self = .metatype
            } else if InspectionVocabulary.isIndexLike(
                only, resolver: resolver, passedToSequenceMethod: sequenceMethod
            ) {
                self = .index(only.trimmedDescription)
            } else {
                self = .other
            }

        case 2:
            let index = arguments[1].expression
            let both = Self.isMetatype(arguments[0].expression)
                && InspectionVocabulary.isIndexLike(index, resolver: resolver)
            self = both ? .metatypeAndIndex(index.trimmedDescription) : .other

        default:
            self = .other
        }
    }

    private static func isMetatype(_ expr: ExprSyntax) -> Bool {
        expr.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "self"
    }

    /// A container is a `Sequence`, so `forEach(check)` and `map(describe)` can be the sequence
    /// methods given a function.
    private static func collidesWithSequence(_ call: FunctionCallExprSyntax) -> Bool {
        let name = call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
        return name == "forEach" || name == "map"
    }
}

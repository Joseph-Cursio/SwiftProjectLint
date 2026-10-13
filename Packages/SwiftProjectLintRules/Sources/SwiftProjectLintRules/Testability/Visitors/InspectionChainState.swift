import SwiftSyntax

/// What ViewInspector hands back at a step, which decides whether the next accessor moves.
///
/// ViewInspector spells a cast and a descent the same way: `x()` takes the receiver's single
/// child and asserts it is an `x`, and `x(0)` takes child 0. Which child that is depends on the
/// receiver, so the receiver's kind — not the accessor's name — says whether a step walks.
enum ReceiverKind {
    /// `inspect()` on an app view. `view(MyView.self)` names its own type, but `x()` falls back to
    /// the body's root.
    case root
    /// A found view — a `ClassifiedView` or `ParentView` — whose only child is itself:
    /// `x()`, `x(0)`, `[0]` and `view(T.self)` check its type in place.
    case found
    /// A slot's content — a label, a header, an overlay — built by a `@ViewBuilder`: `x()` checks
    /// its type in place, but when the builder made several views, `x(0)` picks the first.
    case slot
    /// A view with one child it unwraps: a custom view or modifier's body (`View<T>`,
    /// `ViewModifier<T>`), a relay's view, a sheet's content. `x()` and `x(0)` go one level down.
    case singleChild
    /// A SwiftUI view, or one the rule cannot name. Its children are its layout.
    case typed
}

/// Whose layout a step walks.
enum LayoutOwnership {
    /// The app's: a walk here is reported.
    case app
    /// A view the test file declares, built only from SwiftUI views and other such views.
    case owned
    /// A view the test file declares that builds an app view — a state host wrapping the view
    /// under test. Its own layout is the test's, but a search or a climb may land in the app view.
    case ownedHost

    var ownsLayout: Bool {
        self != .app
    }

    /// Where a search or `parent()` starting here lands: only a tree the test owns throughout
    /// keeps it owned.
    var searched: Self {
        self == .owned ? .owned : .app
    }
}

/// Where an inspected view stands relative to the last place the test searched for it.
struct InspectionChainState {
    /// Levels walked since the chain's anchor — `inspect()`, a `find`, a named slot, a pick
    /// already reported. Reaching the first level asserts what the anchor reached; a second walks.
    var stepsSinceAnchor = 0
    /// Whose layout the inspected subject at the chain's root is. `parent()` climbs out of
    /// whatever the chain reached into that layout.
    var rootOwnership = LayoutOwnership.app
    /// The previous step's accessor, to tell a data index from a layout index.
    var lastStep: String?
    var kind = ReceiverKind.typed
    /// Whose layout the chain is walking: the subject's, or a view the test file declares.
    var ownership = LayoutOwnership.app
    /// The value is `findAll`'s array. `kind` and `matchesOwnership` then describe its elements,
    /// and the only positional moves left are an ordinal: `[n]`, `.last`.
    var isMatchList = false
    var matchesOwnership = LayoutOwnership.app

    /// The layout walked is one the test file declares.
    var ownsLayout: Bool {
        ownership.ownsLayout
    }

    /// A chain's root: `inspect()`, a relay's view, a declared `InspectableView`.
    static func root(_ kind: ReceiverKind, ownership: LayoutOwnership, after step: String? = nil) -> Self {
        Self(stepsSinceAnchor: 0, rootOwnership: ownership, lastStep: step, kind: kind, ownership: ownership)
    }

    /// A new anchor in the same chain: a search, a slot, a pick already reported.
    func reanchored(_ kind: ReceiverKind, ownership: LayoutOwnership, after step: String? = nil) -> Self {
        Self(stepsSinceAnchor: 0, rootOwnership: rootOwnership, lastStep: step, kind: kind, ownership: ownership)
    }

    func advanced(by step: String, to kind: ReceiverKind, ownership: LayoutOwnership) -> Self {
        Self(stepsSinceAnchor: stepsSinceAnchor + 1, rootOwnership: rootOwnership, lastStep: step,
             kind: kind, ownership: ownership)
    }

    var isDataReceiver: Bool {
        lastStep.map(InspectionVocabulary.dataIndexedReceivers.contains) ?? false
    }

    /// An element of this value: a match of a search, a `ForEach` row, a container's child.
    var element: Self {
        guard isMatchList else { return reanchored(.found, ownership: ownership) }
        return reanchored(kind, ownership: matchesOwnership, after: lastStep)
    }

    /// Child 0 of a found view or root is the view itself.
    var isItsOwnFirstChild: Bool {
        kind == .found || kind == .root
    }

    /// `x(0)` reaches the only child, as `x()` does: on a found view, a root or a custom view's
    /// body. On a slot or a SwiftUI container it picks the first of several.
    var hasOnlyChild: Bool {
        kind == .found || kind == .root || kind == .singleChild
    }
}

/// A step that picks a view by where it sits rather than by what it is.
struct PositionalStep {
    enum Kind {
        /// `hStack(1)`, `view(Row.self, 2)` — the step as written.
        case indexed(String)
        /// A second level walked since the anchor — the step as written.
        case descent(String)
        case parent
        /// `[2]`, `.last` or `skipFound: 2` on a search's matches — as written.
        case matchIndex(String)
        /// `[1]`, `.first` or `.last` on a container's children — as written.
        case childIndex(String)
    }

    let kind: Kind
    let node: Syntax
}

/// The state an expression leaves behind, and the first positional step taken inside it.
struct ChainEvaluation {
    var state: InspectionChainState?
    var positionalStep: PositionalStep?

    static let unrelated = Self(state: nil, positionalStep: nil)

    init(state: InspectionChainState?, positionalStep: PositionalStep? = nil) {
        self.state = state
        self.positionalStep = positionalStep
    }

    /// The receiver's positional step comes first in source order, so it wins.
    func then(_ outcome: Self) -> Self {
        Self(state: outcome.state, positionalStep: positionalStep ?? outcome.positionalStep)
    }

    /// The chain ends here, keeping any positional step already taken.
    var ended: Self {
        Self(state: nil, positionalStep: positionalStep)
    }

    /// A positional step, unless the layout it walks belongs to the test.
    static func reporting(
        _ step: PositionalStep,
        from state: InspectionChainState,
        leaving next: InspectionChainState
    ) -> Self {
        Self(state: next, positionalStep: state.ownsLayout ? nil : step)
    }
}

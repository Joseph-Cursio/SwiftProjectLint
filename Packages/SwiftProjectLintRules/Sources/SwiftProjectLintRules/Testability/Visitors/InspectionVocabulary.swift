import SwiftSyntax

/// The parts of ViewInspector's navigation API that Positional View Lookup reads.
///
/// Taken from the library's source at the revision this package pins (6be008f, 0.10.3+28), plus
/// what 0.10.5 adds (`chart`, `tupleContentView`). Matching is by name, so a name here is only
/// ever read on a receiver already known to be an inspected view: `text`, `button`, `list` and
/// `section` mean something else on a `UILabel`, an `XCUIElement` or an `IndexPath`.
enum InspectionVocabulary {

    /// Accessors named after a SwiftUI view type. Each comes as `x()` on a single-content view and
    /// `x(_ index: Int)` on a multiple-content one, so the argument — not the name — says whether
    /// a step picks a sibling by position.
    static let viewTypeAccessors: Set<String> = containers.union(leaves)

    private static let containers: Set<String> = [
        "vStack", "hStack", "zStack", "lazyVStack", "lazyHStack", "lazyVGrid", "lazyHGrid",
        "grid", "gridRow", "group", "form", "list", "section", "forEach", "tabView", "tab",
        "viewThatFits", "hSplitView", "vSplitView", "glassEffectContainer", "groupBox",
        "disclosureGroup", "labeledContent", "menu", "picker", "controlGroup", "navigationView",
        "navigationStack", "navigationSplitView", "navigationLink", "menuButton", "scrollView",
        "scrollViewReader", "geometryReader", "anyView", "view", "tupleView", "tupleContentView",
        "chart"
    ]

    private static let leaves: Set<String> = [
        "text", "button", "image", "label", "link", "toggle", "textField", "secureField",
        "textEditor", "slider", "stepper", "datePicker", "multiDatePicker", "colorPicker",
        "progressView", "contentUnavailableView", "shareLink", "asyncImage", "canvas", "map",
        "outlineGroup", "timelineView", "videoPlayer", "divider", "spacer", "emptyView", "color",
        "shape", "angularGradient", "linearGradient", "radialGradient", "ellipticalGradient",
        "signInWithAppleButton", "pasteButton", "editButton", "locationButton",
        "viewModifierContent", "styleConfigurationLabel", "styleConfigurationContent",
        "styleConfigurationTitle", "styleConfigurationIcon", "styleConfigurationCurrentValueLabel"
    ]

    /// Accessors that reach a view by its role rather than its position: a control's label, a
    /// section's header, a modifier's content. An index on a modifier (`overlay(1)`) counts
    /// modifiers, not layout. After one of these the next step is a cast again, as after `find`.
    static let namedSlots: Set<String> = [
        "labelView", "header", "footer", "icon", "title", "message", "actions", "prompt",
        "description", "sidebarView", "detailView", "contentView", "symbolsView",
        "currentValueLabelView", "videoOverlay", "messageView", "subjectView", "leaf",
        "mapAnnotation", "primaryButton", "secondaryButton",
        "overlay", "background", "mask", "sheet", "fullScreenCover", "popover", "alert",
        "actionSheet", "confirmationDialog", "toolbar", "navigationDestination", "safeAreaInset",
        "safeAreaBar", "listRowBackground", "tabItem", "touchBar",
        "accessibilityActions", "overlayPreferenceValue", "backgroundPreferenceValue"
    ]

    /// Slots whose result unwraps to its content, so the next accessor goes one level down: a
    /// sheet's content, a popover's, a toolbar's. The others return the slot's view itself.
    static let unwrappingSlots: Set<String> = [
        "sheet", "fullScreenCover", "popover", "toolbar", "navigationDestination", "safeAreaInset",
        "safeAreaBar", "touchBar"
    ]

    /// Slots whose index counts items in the order they were declared: `toolbar().item(2)` is the
    /// third `ToolbarItem`, and `navigationBarItems(1)` reads the receiver's second child.
    static let orderedSlots: Set<String> = ["item", "itemGroup", "navigationBarItems"]

    /// Steps after which an index selects a data element rather than a layout sibling: the rows
    /// a `ForEach` generates, and an action sheet's buttons array. Row order is behaviour.
    static let dataIndexedReceivers: Set<String> = ["forEach", "actionSheet"]

    /// Steps that do not move. `implicitAnyView()` unwraps a wrapper only Swift 6.0 inserted and
    /// is a no-op on every other compiler; `classified()` erases the type in place.
    static let transparentSteps: Set<String> = ["implicitAnyView", "classified"]

    /// `find` overloads that return a view of a named SwiftUI type. Every other overload without a
    /// metatype — an identifier, a predicate, a relation — returns the found view itself.
    static let typedFindLabels: Set<String> = ["text", "button", "link", "navigationLink", "textWhere"]

    /// `View.inspect(function:)`, and the style forms: `inspect(isPressed:)`, `inspect(onTrigger:)`, …
    private static let rootLabels: Set<String> = [
        "function", "file", "line", "isPressed", "isOn", "fractionCompleted", "onTrigger"
    ]

    /// `inspect()` returning an inspected root, as opposed to the callback form whose closure is a
    /// relay. The only closure a root takes is `onTrigger:`, an action.
    static func isRootInspect(_ call: FunctionCallExprSyntax) -> Bool {
        let labels = call.arguments.map { $0.label?.text }
        guard labels.allSatisfy({ $0.map(rootLabels.contains) ?? false }) else { return false }
        let relayClosure = call.trailingClosure != nil
            || call.arguments.contains { $0.label?.text != "onTrigger" && $0.expression.is(ClosureExprSyntax.self) }
        return relayClosure == false
    }

    /// `inspect(isPressed:)`, `inspect(isOn:)` and the other style forms: the style's body itself.
    static func isStyleInspect(_ call: FunctionCallExprSyntax) -> Bool {
        call.arguments.contains { styleLabels.contains($0.label?.text ?? "") }
    }

    private static let styleLabels: Set<String> = ["isPressed", "isOn", "fractionCompleted", "onTrigger"]

    /// `NavigationStack`, `HStack`, `Text`: a SwiftUI view type, which ViewInspector names an
    /// accessor after.
    static func isSwiftUIViewType(_ typeName: String) -> Bool {
        viewTypeAccessors.contains(accessorName(forViewType: typeName))
    }

    /// `ViewType.Text` or `ViewInspector.ViewType.Text`: one of ViewInspector's own view types.
    static func isViewTypeName(_ typeName: String) -> Bool {
        typeName.hasPrefix("ViewType.") || typeName.hasPrefix("ViewInspector.ViewType.")
    }

    /// `Outer.Row<Int>` → `Row`: the declared name, without qualifier or generic arguments.
    static func typeName(_ spelled: String) -> String {
        let withoutGenerics = spelled.split(separator: "<", maxSplits: 1).first.map(String.init) ?? spelled
        return withoutGenerics.split(separator: ".").last.map(String.init) ?? withoutGenerics
    }

    /// `ForEach` → `forEach`: the accessor ViewInspector names after a view type.
    static func accessorName(forViewType typeName: String) -> String {
        typeName.prefix(1).lowercased() + typeName.dropFirst()
    }

    /// Anything that could be an `Int`: a literal, a name bound to one, arithmetic, a call. See
    /// `IndexArgumentReader`.
    static func isIndexLike(
        _ expr: ExprSyntax,
        resolver: InspectionBindingResolver?,
        passedToSequenceMethod: Bool = false
    ) -> Bool {
        IndexArgumentReader(resolver: resolver, passedToSequenceMethod: passedToSequenceMethod).isIndexLike(expr)
    }

    /// A subscript key that counts children — `[1]`, `[index]` — rather than naming one, like a
    /// dictionary's `["title"]`.
    static func isPositionalKey(_ arguments: LabeledExprListSyntax, resolver: InspectionBindingResolver) -> Bool {
        guard arguments.count == 1, let only = arguments.first, only.label == nil else { return false }
        return isIndexLike(only.expression, resolver: resolver)
    }
}

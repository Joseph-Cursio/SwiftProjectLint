import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// The parts of the Computed Property View gate that read the *shape* of a type rather than drive
/// the walk: which containers decompose their contents, how a property's dependencies resolve, and
/// how a name is read out of an expression.
///
/// Split from `ComputedPropertyViewVisitor` when the extension-member gate pushed the class body
/// past `type_body_length`. Nothing here touches visitor state — every member is `static`.
extension ComputedPropertyViewVisitor {

    /// APIs that **decompose** the closure they are handed instead of rendering it as one view.
    ///
    /// Two families, one argument. `confirmationDialog(actions:)`, `alert(actions:)`,
    /// `Menu(content:)` and `contextMenu` read a *collection of buttons* out of the builder.
    /// `ToolbarItem(content:)`, `ToolbarItemGroup(content:)` and `.toolbar` read a *collection of
    /// toolbar items* out of theirs. In both cases a `View` struct wrapping the contents is a
    /// container the API is not specified to accept, so "extract this into its own View" is not
    /// behaviour-preserving — it is the one place where following this rule can change what the app
    /// does rather than only how it redraws.
    ///
    /// The toolbar half is visible in the corpus rather than argued: `ViolationInspectorView`'s
    /// `navigationButtons` is a `Group` of two `Button`s inside a `ToolbarItemGroup`, which places
    /// **two** items. Wrapped in a `View` struct it is one view, and the group places **one**.
    /// `actionsMenu` is worse — an `if` around a `Menu`, so extraction also fixes the item count
    /// that the condition currently varies.
    ///
    /// Deliberately coarse in the same direction as the dialog half: a property that happens to be
    /// the *only* view in its `ToolbarItem` could be extracted safely, and is spared anyway. A
    /// spared property costs a finding; a reported one whose extraction drops a toolbar button
    /// costs a working app.
    ///
    /// The dialog half was found on MacCloud_client_iOS, where `FileListView` had three such
    /// properties and the rule reported all three — marked `info` for carrying `@ViewBuilder`,
    /// which is not the same thing as declining to report them.
    static let decomposingContainers: Set<String> = [
        "confirmationDialog", "alert", "actionSheet", "Menu", "contextMenu",
        "ToolbarItem", "ToolbarItemGroup", "toolbar"
    ]

    /// Property names referenced inside one of those containers.
    ///
    /// Only the *arguments and trailing closures* are searched, never the called expression. For a
    /// modifier the called expression holds the receiver — the entire view it is applied to — and
    /// walking it would sweep up every name in `body`.
    ///
    /// Deliberately coarse in one direction: a name appearing in `alert`'s `message:` closure is
    /// spared along with the ones in `actions:`. Sparing a property costs a finding; reporting one
    /// whose extraction breaks a dialog or drops a toolbar button costs a working app, so the
    /// imprecision is pointed the safe way.
    static func namesUsedByDecomposingContainers(in memberBlock: MemberBlockSyntax) -> Set<String> {
        var found: Set<String> = []
        collectDecomposedNames(in: Syntax(memberBlock), into: &found)
        return found
    }

    static func collectDecomposedNames(in node: Syntax, into found: inout Set<String>) {
        for child in node.children(viewMode: .sourceAccurate) {
            if let call = child.as(FunctionCallExprSyntax.self), isDecomposingContainer(call) {
                found.formUnion(referencedNames(in: Syntax(call.arguments)))
                if let trailing = call.trailingClosure {
                    found.formUnion(referencedNames(in: Syntax(trailing)))
                }
                for extra in call.additionalTrailingClosures {
                    found.formUnion(referencedNames(in: Syntax(extra.closure)))
                }
            }
            collectDecomposedNames(in: child, into: &found)
        }
    }

    static func isDecomposingContainer(_ call: FunctionCallExprSyntax) -> Bool {
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return decomposingContainers.contains(member.declName.baseName.text)
        }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return decomposingContainers.contains(reference.baseName.text)
        }
        return false
    }

    /// The stored properties a computed property reaches, following the type's other computed
    /// properties. A wrapper that reads nothing itself still depends on whatever it calls.
    static func resolvedDependencies(
        of name: String,
        computed: [String: Set<String>],
        stored: Set<String>
    ) -> Set<String> {
        var seen: Set<String> = [name]
        var pending = Array(computed[name] ?? [])
        var result: Set<String> = []

        while let next = pending.popLast() {
            if stored.contains(next) { result.insert(next) }
            guard !seen.contains(next) else { continue }
            seen.insert(next)
            if let further = computed[next] { pending.append(contentsOf: further) }
        }
        return result
    }

    /// Every name referenced in `node`, **including `node` itself**.
    ///
    /// The self-inclusion is the whole point, and it was missing. This walked only the children, so
    /// a caller handing it a bare `DeclReferenceExprSyntax` got back the empty set — the node it
    /// asked about was the one node never examined.
    ///
    /// Every other caller passes a container (an accessor block, an argument list, a closure), for
    /// which a root that is itself a reference is impossible, so the gap was invisible from all of
    /// them but one. The exception was `requiresCapture`'s `toggle` check, which passes the base of
    /// `isExpanded.toggle()` and therefore **never once fired** — `isExpanded = true` was gated and
    /// `isExpanded.toggle()` was reported, the same mutation under two spellings.
    ///
    /// `assignedNames` had already hit this and worked around it in place, re-inserting the
    /// element's own name after calling here. That workaround is now redundant and is kept only
    /// because it also handles a member access this function deliberately does not.
    static func referencedNames(in node: Syntax) -> Set<String> {
        var names: Set<String> = []
        insertReference(at: node, into: &names)
        for child in node.children(viewMode: .sourceAccurate) {
            names.formUnion(referencedNames(in: child))
        }
        return names
    }

    /// The name `node` refers to, if it refers to one. A member access counts only through
    /// `self`, because `other.property` is a reference to `other` and not to `property`.
    static func insertReference(at node: Syntax, into names: inout Set<String>) {
        if let reference = node.as(DeclReferenceExprSyntax.self) {
            names.insert(stripped(reference.baseName.text))
        }
        if let member = node.as(MemberAccessExprSyntax.self),
           member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind
            == .keyword(.self) {
            names.insert(member.declName.baseName.text)
        }
    }

    /// Whether `type` is a function type, seeing through the wrappers a callback is usually
    /// declared with.
    ///
    /// `() -> Void`, `(() -> Void)?` and `@escaping (Template) -> Void` are all the same thing for
    /// this purpose, and the corpus writes all three. An optional wraps a *parenthesised* function
    /// type, which parses as a one-element tuple, so the tuple case is what makes the optional
    /// spelling work rather than an accident.
    static func isFunctionType(_ type: TypeSyntax?) -> Bool {
        guard let type else { return false }
        if type.is(FunctionTypeSyntax.self) { return true }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return isFunctionType(optional.wrappedType)
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return isFunctionType(attributed.baseType)
        }
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
           let only = tuple.elements.first {
            return isFunctionType(only.type)
        }
        return false
    }

    /// `$isExpanded` and `isExpanded` are the same input.
    ///
    /// The projected value of a `@State` or `@Binding` parses as its own identifier, so a property
    /// that writes through `$isExpanded` reads as depending on nothing. That is not academic: a
    /// `Toggle(_:isOn:)` is the ordinary way to touch that state, and without this every wrapper
    /// around one looked input-free and fired.
    static func stripped(_ name: String) -> String {
        name.hasPrefix("$") ? String(name.dropFirst()) : name
    }

    static func returnsSomeViewType(_ annotation: TypeAnnotationSyntax?) -> Bool {
        guard let annotation,
              let someType = annotation.type.as(SomeOrAnyTypeSyntax.self) else { return false }
        return someType.constraint.trimmedDescription == "View"
    }
}

import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects computed properties returning `some View` whose extraction would actually buy something.
///
/// The mechanism is real: a computed property returning `some View` is inlined into the parent's
/// `body` and has no node of its own in the view graph, so it re-evaluates whenever the parent
/// does. A child `View` struct gets an identity, can skip its `body` when its inputs compare equal,
/// and can hold its own `@State`.
///
/// **The benefit is conditional, and the rule used to report it unconditionally.** A child only
/// skips an update when its inputs are narrower than its parent's. Extract `SummaryRow(issue:)` out
/// of a view that re-renders whenever `issue` changes and the child re-renders in lockstep — the
/// same work, one more type. Measured on this project's own app, seven of the eighteen findings had
/// exactly that shape.
///
/// So the property must depend on a **strict subset** of the enclosing type's stored inputs. That
/// is a necessary condition for the diffing benefit, not a sufficient one — a two-line `Text` gains
/// little either way — but it is the condition the rule can actually check, and it is what
/// separates a property that can skip an update from one that never will.
///
/// Dependencies are followed **transitively** through the type's other computed properties: a
/// property that reads nothing itself but calls one that reads `isExpanded` depends on
/// `isExpanded`. Without that, every wrapper property looks input-free and every one of them fires.
class ComputedPropertyViewVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""
    private var isInsideViewType = false

    /// Names of the view properties in the type currently being visited that pass the subset gate.
    /// Computed once per type, because the answer depends on the type's other members.
    private var firingNames: Set<String> = []

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    // MARK: - Track View-conforming types

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToView(node.inheritanceClause) || hasBodySomeView(node.memberBlock) {
            isInsideViewType = true
            firingNames = Self.propertiesWorthExtracting(in: node.memberBlock)
        }
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) {
        isInsideViewType = false
        firingNames = []
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToView(node.inheritanceClause) || hasBodySomeView(node.memberBlock) {
            isInsideViewType = true
            firingNames = Self.propertiesWorthExtracting(in: node.memberBlock)
        }
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) {
        isInsideViewType = false
        firingNames = []
    }

    // MARK: - Detect computed properties returning some View

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isInsideViewType else { return .visitChildren }

        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  name != "body",
                  returnsSomeView(binding.typeAnnotation),
                  binding.accessorBlock != nil,
                  firingNames.contains(name) else {
                continue
            }

            let hasViewBuilder = node.attributes.contains { attr in
                guard let attrSyntax = attr.as(AttributeSyntax.self) else { return false }
                return attrSyntax.attributeName.trimmedDescription == "ViewBuilder"
            }

            let severity: IssueSeverity = hasViewBuilder ? .info : .warning
            let qualifier = hasViewBuilder ? " @ViewBuilder" : ""

            addIssue(
                severity: severity,
                message: "Computed\(qualifier) property '\(name)' returns 'some View' and depends "
                    + "on fewer of this view's inputs than the view itself — extract it into a "
                    + "separate View struct so SwiftUI can skip it when the inputs it ignores change",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Move '\(name)' into its own struct conforming to View",
                ruleName: .computedPropertyView
            )
        }
        return .skipChildren
    }

    // MARK: - The subset gate

    /// Which `some View` properties in a type would gain a narrower input surface by extraction.
    ///
    /// Returns the properties whose transitive dependency on the type's stored properties is a
    /// *strict* subset of those stored properties. A property depending on all of them re-renders
    /// exactly when its parent does, so a child struct changes nothing; a type with no stored
    /// properties at all has nothing to narrow, and yields nothing.
    static func propertiesWorthExtracting(in memberBlock: MemberBlockSyntax) -> Set<String> {
        let members = properties(of: memberBlock)
        guard !members.stored.isEmpty else { return [] }

        let buttonCollections = namesUsedAsButtonCollections(in: memberBlock)

        return members.viewProperties.filter { name in
            guard !buttonCollections.contains(name),
                  !requiresCapture(name, in: members) else { return false }
            let depends = resolvedDependencies(
                of: name, computed: members.computedReferences, stored: members.stored
            )
            return depends.isSubset(of: members.stored) && depends.count < members.stored.count
        }
    }

    /// Whether extracting this property would force a `Binding` or a capturing closure across the
    /// boundary — in which case SwiftUI cannot skip the child and the extraction buys nothing.
    ///
    /// **Measured, not assumed.** A harness counting `body` evaluations while changing state no
    /// child reads (iOS 26.5, three changes): a child with no inputs, a value input, or a
    /// *non-capturing* closure re-rendered **0** times; a child holding a `@Binding` or a
    /// *capturing* closure re-rendered **3** — once per change, exactly as often as the inlined
    /// property it replaced.
    ///
    /// The distinction is capture, not closures. `action: { }` compiles to one static function and
    /// compares equal; `action: { showingSheet = true }` allocates a fresh context on every parent
    /// body run, so the child value never compares equal. A `Binding` carries a getter and setter
    /// and behaves the same way.
    ///
    /// Three shapes force it: reading a stored property's projected value (`$name`), assigning to
    /// one, or calling one of the type's own methods. Followed transitively — a property composing
    /// children that each need a binding needs to pass those bindings down.
    private static func requiresCapture(_ name: String, in members: TypeProperties) -> Bool {
        var seen: Set<String> = []
        var pending = [name]

        while let current = pending.popLast() {
            guard seen.insert(current).inserted else { continue }
            let captures = members.capturesFor[current] ?? []
            if !captures.isDisjoint(with: members.stored) { return true }
            let referenced = members.computedReferences[current] ?? []
            if !referenced.isDisjoint(with: members.instanceMethods) { return true }
            pending.append(contentsOf: referenced.filter { members.computedReferences[$0] != nil })
        }
        return false
    }

    /// The names on the left of the first `=` in an unfolded operator sequence.
    private static func assignedNames(in sequence: SequenceExprSyntax) -> Set<String> {
        var names: Set<String> = []
        for element in sequence.elements {
            if element.is(AssignmentExprSyntax.self) { return names }
            names.formUnion(referencedNames(in: Syntax(element)))
            if let reference = element.as(DeclReferenceExprSyntax.self) {
                names.insert(stripped(reference.baseName.text))
            }
            if let member = element.as(MemberAccessExprSyntax.self) {
                names.insert(member.declName.baseName.text)
            }
        }
        return []
    }

    /// Names used as a projected value (`$name`) or written to.
    ///
    /// `referencedNames` cannot answer this: it strips the `$` so that `$isExpanded` counts as a
    /// dependency on `isExpanded`, which is right for the narrowing gate and loses exactly the
    /// distinction needed here.
    private static func projectedAndAssignedNames(in node: Syntax) -> Set<String> {
        var names: Set<String> = []
        for child in node.children(viewMode: .sourceAccurate) {
            if let reference = child.as(DeclReferenceExprSyntax.self),
               reference.baseName.text.hasPrefix("$") {
                names.insert(String(reference.baseName.text.dropFirst()))
            }
            // `showing = true` parses as an *unfolded* `SequenceExprSyntax` — the plain parser
            // does not fold operators, so `InfixOperatorExprSyntax` never appears here. The names
            // before the first `=` are the ones being written to.
            if let sequence = child.as(SequenceExprSyntax.self) {
                names.formUnion(assignedNames(in: sequence))
            }
            if let call = child.as(FunctionCallExprSyntax.self),
               let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               member.declName.baseName.text == "toggle", let base = member.base {
                names.formUnion(referencedNames(in: Syntax(base)))
            }
            names.formUnion(projectedAndAssignedNames(in: child))
        }
        return names
    }

    private struct TypeProperties {
        var stored: Set<String> = []
        var computedReferences: [String: Set<String>] = [:]
        var viewProperties: Set<String> = []
        /// Non-static methods of the enclosing type. Referencing one means the extracted child
        /// would have to be handed a closure that captures the parent.
        var instanceMethods: Set<String> = []
        /// Per computed property: the names it uses as a projected value (`$name`) and the names
        /// it assigns to. Both force a `Binding` or a capturing closure across the boundary.
        var capturesFor: [String: Set<String>] = [:]
    }

    /// The type's stored inputs, what each computed property references, and which of them return
    /// `some View`.
    private static func properties(of memberBlock: MemberBlockSyntax) -> TypeProperties {
        var result = TypeProperties()
        for member in memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self),
               !function.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) {
                result.instanceMethods.insert(function.name.text)
            }
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isStatic = varDecl.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
            for binding in varDecl.bindings {
                record(binding, isStatic: isStatic, into: &result)
            }
        }
        return result
    }

    private static func record(
        _ binding: PatternBindingSyntax, isStatic: Bool, into result: inout TypeProperties
    ) {
        guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?
            .identifier.text else { return }
        guard let accessor = binding.accessorBlock else {
            // A stored property. `static let` is a constant, not an input the view re-renders on,
            // so it is not part of the surface.
            if !isStatic { result.stored.insert(name) }
            return
        }
        result.computedReferences[name] = referencedNames(in: Syntax(accessor))
        result.capturesFor[name] = projectedAndAssignedNames(in: Syntax(accessor))
        if name != "body", returnsSomeViewType(binding.typeAnnotation) {
            result.viewProperties.insert(name)
        }
    }

    /// APIs whose closure is a **collection of buttons**, not an arbitrary view.
    ///
    /// `confirmationDialog(actions:)`, `alert(actions:)`, `Menu(content:)` and `contextMenu` read
    /// the buttons out of the builder they are handed. A `View` struct wrapping those buttons is a
    /// container these APIs are not specified to accept, so "extract this into its own View" is not
    /// behaviour-preserving here — it is the one place where following this rule can change what
    /// the app does rather than only how it redraws.
    ///
    /// Found on MacCloud_client_iOS, where `FileListView` had three such properties and the rule
    /// reported all three. It marked them `info` for carrying `@ViewBuilder`, which is not the same
    /// thing as declining to report them.
    private static let buttonCollectionBuilders: Set<String> = [
        "confirmationDialog", "alert", "actionSheet", "Menu", "contextMenu"
    ]

    /// Property names referenced inside one of those builders.
    ///
    /// Only the *arguments and trailing closures* are searched, never the called expression. For a
    /// modifier the called expression holds the receiver — the entire view it is applied to — and
    /// walking it would sweep up every name in `body`.
    ///
    /// Deliberately coarse in one direction: a name appearing in `alert`'s `message:` closure is
    /// spared along with the ones in `actions:`. Sparing a property costs a finding; reporting one
    /// whose extraction breaks a dialog costs a working app, so the imprecision is pointed the safe
    /// way.
    private static func namesUsedAsButtonCollections(in memberBlock: MemberBlockSyntax) -> Set<String> {
        var found: Set<String> = []
        collectButtonCollectionNames(in: Syntax(memberBlock), into: &found)
        return found
    }

    private static func collectButtonCollectionNames(in node: Syntax, into found: inout Set<String>) {
        for child in node.children(viewMode: .sourceAccurate) {
            if let call = child.as(FunctionCallExprSyntax.self), isButtonCollection(call) {
                found.formUnion(referencedNames(in: Syntax(call.arguments)))
                if let trailing = call.trailingClosure {
                    found.formUnion(referencedNames(in: Syntax(trailing)))
                }
                for extra in call.additionalTrailingClosures {
                    found.formUnion(referencedNames(in: Syntax(extra.closure)))
                }
            }
            collectButtonCollectionNames(in: child, into: &found)
        }
    }

    private static func isButtonCollection(_ call: FunctionCallExprSyntax) -> Bool {
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return buttonCollectionBuilders.contains(member.declName.baseName.text)
        }
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return buttonCollectionBuilders.contains(reference.baseName.text)
        }
        return false
    }

    /// The stored properties a computed property reaches, following the type's other computed
    /// properties. A wrapper that reads nothing itself still depends on whatever it calls.
    private static func resolvedDependencies(
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
    private static func referencedNames(in node: Syntax) -> Set<String> {
        var names: Set<String> = []
        insertReference(at: node, into: &names)
        for child in node.children(viewMode: .sourceAccurate) {
            names.formUnion(referencedNames(in: child))
        }
        return names
    }

    /// The name `node` refers to, if it refers to one. A member access counts only through
    /// `self`, because `other.property` is a reference to `other` and not to `property`.
    private static func insertReference(at node: Syntax, into names: inout Set<String>) {
        if let reference = node.as(DeclReferenceExprSyntax.self) {
            names.insert(stripped(reference.baseName.text))
        }
        if let member = node.as(MemberAccessExprSyntax.self),
           member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind
            == .keyword(.self) {
            names.insert(member.declName.baseName.text)
        }
    }

    /// `$isExpanded` and `isExpanded` are the same input.
    ///
    /// The projected value of a `@State` or `@Binding` parses as its own identifier, so a property
    /// that writes through `$isExpanded` reads as depending on nothing. That is not academic: a
    /// `Toggle(_:isOn:)` is the ordinary way to touch that state, and without this every wrapper
    /// around one looked input-free and fired.
    private static func stripped(_ name: String) -> String {
        name.hasPrefix("$") ? String(name.dropFirst()) : name
    }

    private static func returnsSomeViewType(_ annotation: TypeAnnotationSyntax?) -> Bool {
        guard let annotation,
              let someType = annotation.type.as(SomeOrAnyTypeSyntax.self) else { return false }
        return someType.constraint.trimmedDescription == "View"
    }

    // MARK: - Helpers

    private func conformsToView(_ clause: InheritanceClauseSyntax?) -> Bool {
        guard let clause else { return false }
        return clause.inheritedTypes.contains { inherited in
            inherited.type.trimmedDescription == "View"
        }
    }

    private func hasBodySomeView(_ memberBlock: MemberBlockSyntax) -> Bool {
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      name == "body",
                      returnsSomeView(binding.typeAnnotation) else {
                    continue
                }
                return true
            }
        }
        return false
    }

    private func returnsSomeView(_ annotation: TypeAnnotationSyntax?) -> Bool {
        guard let annotation else { return false }
        guard let someType = annotation.type.as(SomeOrAnyTypeSyntax.self) else { return false }
        return someType.constraint.trimmedDescription == "View"
    }
}

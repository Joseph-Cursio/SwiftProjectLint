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

    /// The member blocks of every `extension` in the file under analysis, keyed by extended type.
    ///
    /// A type's members are routinely spread over `Foo.swift` and `Foo+Sections.swift`, and the
    /// gate below needs the whole type: a property forwarding to a sibling it cannot see reads as
    /// depending on *nothing*, which is the strongest possible pass. This closes the half of that
    /// gap visible from one file; `knownExtensionMembers` closes the other half by declining.
    private var fileExtensions: [String: [MemberBlockSyntax]] = [:]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    /// The file's own extensions, gathered before any type is visited.
    ///
    /// `SourceFileSyntax` is the root, so this runs first and `fileExtensions` is populated by the
    /// time any `struct` or `class` is reached — including one declared after the extension.
    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        fileExtensions = [:]
        collectExtensions(in: Syntax(node))
        return .visitChildren
    }

    private func collectExtensions(in node: Syntax) {
        for child in node.children(viewMode: .sourceAccurate) {
            if let extensionDecl = child.as(ExtensionDeclSyntax.self),
               let name = ExtensionMemberCollector.extendedTypeName(extensionDecl.extendedType) {
                fileExtensions[name, default: []].append(extensionDecl.memberBlock)
            }
            collectExtensions(in: child)
        }
    }

    /// The members of `typeName` this file cannot see: declared in an extension somewhere in the
    /// project, and not in any extension here.
    ///
    /// Empty when no pre-scan ran, which is the right answer for a visitor driven by a unit test —
    /// one file hides nothing from itself.
    private func hiddenMembers(of typeName: String) -> Set<String> {
        let elsewhere = knownExtensionMembers.members(on: typeName)
        guard !elsewhere.isEmpty else { return [] }
        let here = (fileExtensions[typeName] ?? [])
            .reduce(into: Set<String>()) { $0.formUnion(ExtensionMemberCollector.memberNames(in: $1)) }
        return elsewhere.subtracting(here)
    }

    /// Every member block that makes up `typeName` in this file: its declaration and its
    /// same-file extensions.
    private func memberBlocks(for typeName: String, declaration: MemberBlockSyntax) -> [MemberBlockSyntax] {
        [declaration] + (fileExtensions[typeName] ?? [])
    }

    // MARK: - Track View-conforming types

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToView(node.inheritanceClause) || hasBodySomeView(node.memberBlock) {
            isInsideViewType = true
            firingNames = Self.propertiesWorthExtracting(
                in: memberBlocks(for: node.name.text, declaration: node.memberBlock),
                hiddenMembers: hiddenMembers(of: node.name.text)
            )
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
            firingNames = Self.propertiesWorthExtracting(
                in: memberBlocks(for: node.name.text, declaration: node.memberBlock),
                hiddenMembers: hiddenMembers(of: node.name.text)
            )
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
    static func propertiesWorthExtracting(
        in memberBlocks: [MemberBlockSyntax],
        hiddenMembers: Set<String> = []
    ) -> Set<String> {
        let members = properties(of: memberBlocks)
        guard !members.stored.isEmpty else { return [] }

        let decomposed = memberBlocks.reduce(into: Set<String>()) {
            $0.formUnion(namesUsedByDecomposingContainers(in: $1))
        }

        return members.viewProperties.filter { name in
            guard !decomposed.contains(name),
                  !requiresCapture(name, in: members),
                  !reachesHiddenMember(name, in: members, hidden: hiddenMembers) else { return false }
            let depends = resolvedDependencies(
                of: name, computed: members.computedReferences, stored: members.stored
            )
            return depends.isSubset(of: members.stored) && depends.count < members.stored.count
        }
    }

    /// Whether the property reaches a member declared in an extension this file cannot see.
    ///
    /// **The gate's premise is that the dependency set is known**, and for a type split across
    /// files it is not. Worse, the failure is silent and one-directional: an unseen sibling
    /// contributes no dependencies, so a property that forwards to one reads as depending on
    /// nothing — the strongest possible pass. The rule was most confident exactly where it knew
    /// least.
    ///
    /// Measured on SwiftLintRuleStudio: 7 of 20 findings sat in types split across files.
    /// `RuleAuditView.auditResultsView` composes two extension properties that between them read
    /// six stored properties and call four instance methods — with the whole type in view the
    /// capture gate declines it outright.
    ///
    /// Followed transitively, for the same reason the other two gates are: a wrapper that forwards
    /// to a wrapper that forwards to an unseen sibling knows no more than the sibling does.
    private static func reachesHiddenMember(
        _ name: String, in members: TypeProperties, hidden: Set<String>
    ) -> Bool {
        guard !hidden.isEmpty else { return false }
        var seen: Set<String> = []
        var pending = [name]

        while let current = pending.popLast() {
            guard seen.insert(current).inserted else { continue }
            let referenced = members.computedReferences[current] ?? []
            if !referenced.isDisjoint(with: hidden) { return true }
            pending.append(contentsOf: referenced.filter { members.computedReferences[$0] != nil })
        }
        return false
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
            if !referenced.isDisjoint(with: members.closureInputs) { return true }
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
        /// Stored properties whose declared type is a function — the callbacks a view is handed.
        /// Forwarding one to a child puts that closure across the boundary just as creating one
        /// does.
        var closureInputs: Set<String> = []
    }

    /// The type's stored inputs, what each computed property references, and which of them return
    /// `some View`.
    private static func properties(of memberBlocks: [MemberBlockSyntax]) -> TypeProperties {
        var result = TypeProperties()
        for member in memberBlocks.flatMap(\.members) {
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
            if !isStatic {
                result.stored.insert(name)
                if isFunctionType(binding.typeAnnotation?.type) { result.closureInputs.insert(name) }
            }
            return
        }
        result.computedReferences[name] = referencedNames(in: Syntax(accessor))
        result.capturesFor[name] = projectedAndAssignedNames(in: Syntax(accessor))
        if name != "body", returnsSomeViewType(binding.typeAnnotation) {
            result.viewProperties.insert(name)
        }
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

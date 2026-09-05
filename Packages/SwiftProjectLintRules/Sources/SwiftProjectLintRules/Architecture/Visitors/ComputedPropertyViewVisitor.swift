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
        var stored: Set<String> = []
        var computedReferences: [String: Set<String>] = [:]
        var viewProperties: Set<String> = []

        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isStatic = varDecl.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
            for binding in varDecl.bindings {
                guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?
                    .identifier.text else { continue }
                guard let accessor = binding.accessorBlock else {
                    // A stored property. `static let` is a constant, not an input the view
                    // re-renders on, so it is not part of the surface.
                    if !isStatic { stored.insert(name) }
                    continue
                }
                computedReferences[name] = referencedNames(in: Syntax(accessor))
                if name != "body", returnsSomeViewType(binding.typeAnnotation) {
                    viewProperties.insert(name)
                }
            }
        }
        guard !stored.isEmpty else { return [] }

        return viewProperties.filter { name in
            let depends = resolvedDependencies(of: name, computed: computedReferences, stored: stored)
            return depends.isSubset(of: stored) && depends.count < stored.count
        }
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

    private static func referencedNames(in node: Syntax) -> Set<String> {
        var names: Set<String> = []
        for child in node.children(viewMode: .sourceAccurate) {
            if let reference = child.as(DeclReferenceExprSyntax.self) {
                names.insert(stripped(reference.baseName.text))
            }
            if let member = child.as(MemberAccessExprSyntax.self),
               member.base?.as(DeclReferenceExprSyntax.self)?.baseName.tokenKind
                == .keyword(.self) {
                names.insert(member.declName.baseName.text)
            }
            names.formUnion(referencedNames(in: child))
        }
        return names
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

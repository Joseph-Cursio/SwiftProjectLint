import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A cross-file visitor that detects top-level types with internal (default) access
/// that are only referenced in their declaring file and could be narrowed to `private`.
///
/// **Phase 1 (walk):** Collects all top-level type declarations and all type references
/// across every file.
/// **Phase 2 (finalizeAnalysis):** Compares declarations against references. Types that
/// are never referenced outside their declaring file are flagged.
final class CouldBePrivateVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// Tracks where each type name is declared: typeName → fileName
    private var declarations: [(name: String, file: String, node: Syntax)] = []

    /// Tracks which files reference each type name: typeName → Set<fileName>
    private var references: [String: Set<String>] = [:]

    /// All declared type names (to avoid flagging references to external types).
    private var declaredTypeNames: Set<String> = []

    /// Protocol names declared in the project.
    private var projectProtocolNames: Set<String> = []

    /// Maps type name → set of protocol names it conforms to.
    private var typeConformances: [String: Set<String>] = [:]

    /// Type names appearing in the type annotation of a non-private member, keyed by the
    /// file that member is declared in: file → Set<typeName>.
    ///
    /// These are part of that file's accessible surface even when no other file ever
    /// writes the name. A caller reaching `cache.entries["k"]` receives a value of the
    /// element type through inference; making that type `private` stops the code
    /// compiling although nothing outside the file names it.
    private var accessibleInterfaceTypes: [String: Set<String>] = [:]

    /// Depth inside type bodies, so member declarations can be told from top-level ones
    /// when collecting interface types. Incremented unconditionally on entering a type
    /// declaration and decremented in `visitPost`: the entry points below `guard` past
    /// their body for `@main` and `App` types, and `visitPost` still runs for those, so
    /// counting only after the guard would leave the depth permanently skewed.
    private var typeNestingDepth: Int = 0

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        typeNestingDepth = 0
    }

    // MARK: - Collect Declarations (top-level, internal access only)

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNestingDepth += 1
        // Skip App entry points and @main types — they can't be private
        guard !isSwiftUIApp(node), !hasMainAttribute(node.attributes) else { return .visitChildren }
        collectDeclarationIfEligible(node.name.text, modifiers: node.modifiers, node: Syntax(node))
        trackProtocolConformance(node.name.text, inheritance: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) { typeNestingDepth -= 1 }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNestingDepth += 1
        collectDeclarationIfEligible(node.name.text, modifiers: node.modifiers, node: Syntax(node))
        trackProtocolConformance(node.name.text, inheritance: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) { typeNestingDepth -= 1 }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNestingDepth += 1
        collectDeclarationIfEligible(node.name.text, modifiers: node.modifiers, node: Syntax(node))
        trackProtocolConformance(node.name.text, inheritance: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ _: EnumDeclSyntax) { typeNestingDepth -= 1 }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNestingDepth += 1
        collectDeclarationIfEligible(node.name.text, modifiers: node.modifiers, node: Syntax(node))
        trackProtocolConformance(node.name.text, inheritance: node.inheritanceClause)
        return .visitChildren
    }

    override func visitPost(_ _: ActorDeclSyntax) { typeNestingDepth -= 1 }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNestingDepth += 1
        projectProtocolNames.insert(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ProtocolDeclSyntax) { typeNestingDepth -= 1 }

    // MARK: - Collect the file's accessible interface types

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard typeNestingDepth > 0, !isPrivate(node.modifiers) else { return .visitChildren }
        if let annotation = node.bindings.first?.typeAnnotation?.type {
            collectTypeNames(
                from: annotation,
                into: &accessibleInterfaceTypes[currentFilePath, default: []]
            )
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard typeNestingDepth > 0, !isPrivate(node.modifiers) else { return .visitChildren }
        if let returnType = node.signature.returnClause?.type {
            collectTypeNames(
                from: returnType,
                into: &accessibleInterfaceTypes[currentFilePath, default: []]
            )
        }
        return .visitChildren
    }

    // MARK: - Collect References

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        references[node.name.text, default: []].insert(currentFilePath)
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text
        // Only track references that start with uppercase (type names)
        if let first = name.first, first.isUppercase {
            references[name, default: []].insert(currentFilePath)
        }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Track Type.member patterns (e.g., Severity.error)
        if let base = node.base?.as(DeclReferenceExprSyntax.self) {
            let name = base.baseName.text
            if let first = name.first, first.isUppercase {
                references[name, default: []].insert(currentFilePath)
            }
        }
        // Track Type.self metatype references (e.g., [MyRule.self])
        if node.declName.baseName.text == "self",
           let base = node.base?.as(DeclReferenceExprSyntax.self) {
            let name = base.baseName.text
            if let first = name.first, first.isUppercase {
                references[name, default: []].insert(currentFilePath)
            }
        }
        return .visitChildren
    }

    // MARK: - Finalize

    func finalizeAnalysis() {
        for decl in declarations {
            // Suppress types conforming to project-defined protocols —
            // likely used polymorphically (metatype arrays, DI, etc.)
            if let conformances = typeConformances[decl.name],
               conformances.isEmpty == false,
               conformances.contains(where: { projectProtocolNames.contains($0) }) {
                continue
            }

            // Skip types on the declaring file's accessible surface. No other file needs
            // to name the type for a caller to hold values of it — inference hands them
            // over — so "unreferenced elsewhere" does not mean "safe to narrow".
            if accessibleInterfaceTypes[decl.file]?.contains(decl.name) == true { continue }

            let referencingFiles = references[decl.name] ?? []
            // Remove the declaring file — we only care about external references
            let externalFiles = referencingFiles.subtracting([decl.file])

            if externalFiles.isEmpty {
                let carriesCandidates = declaresPropertyTestCandidate(decl.node)
                let cost = carriesCandidates
                    ? " — but it declares a property-based-test candidate, and a `private` type is "
                        + "beyond `@testable import`, which reaches `internal` and no further. "
                        + "Narrowing it means no test can construct it."
                    : ""
                let advice = carriesCandidates
                    ? "Leave it `internal` if you intend to property-test what it declares. Making "
                        + "the type private hides its members just as effectively as marking each "
                        + "of them private."
                    : "Add `private` access to narrow the scope of '\(decl.name)'."

                addIssue(
                    severity: .info,
                    message: "'\(decl.name)' is only used in its declaring file "
                        + "and could be private" + cost,
                    filePath: decl.file,
                    lineNumber: getLineNumber(for: decl.node),
                    suggestion: advice,
                    ruleName: .couldBePrivate
                )
            }
        }
    }

    /// Whether `node` — a type declaration — declares any function that is a property-test
    /// candidate.
    ///
    /// A `private` type puts every one of its members beyond `@testable import`, so narrowing the
    /// type costs exactly what narrowing each member would. Advising it without saying so would
    /// take away the property tests by a side door.
    private func declaresPropertyTestCandidate(_ node: Syntax) -> Bool {
        let collector = CandidateFunctionCollector(
            knownEquatableTypes: knownEquatableTypes,
            viewMode: .sourceAccurate
        )
        collector.walk(node)
        return collector.foundCandidate
    }

    // MARK: - Helpers

    private func collectDeclarationIfEligible(
        _ name: String,
        modifiers: DeclModifierListSyntax,
        node: Syntax
    ) {
        // Only flag top-level declarations
        guard isTopLevel(node) else { return }

        // Skip test/example/fixture files
        if isTestOrFixtureFile() {
            return
        }

        // Skip types that already have explicit access control
        guard !modifiers.hasExplicitAccessControl else { return }

        declarations.append((name: name, file: currentFilePath, node: node))
        declaredTypeNames.insert(name)
    }

    private func isPrivate(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { $0.name.text == "private" || $0.name.text == "fileprivate" }
    }

    /// Collects every type name written inside `type`, descending through the shapes a
    /// member's annotation can take. `[String: RemovalEntry]` must yield `RemovalEntry`,
    /// not just `Dictionary`, or the member exposing it goes unnoticed.
    private func collectTypeNames(from type: TypeSyntax, into set: inout Set<String>) {
        if let ident = type.as(IdentifierTypeSyntax.self) {
            set.insert(ident.name.text)
            for argument in ident.genericArgumentClause?.arguments ?? [] {
                if let argumentType = argument.argument.as(TypeSyntax.self) {
                    collectTypeNames(from: argumentType, into: &set)
                }
            }
            return
        }
        // `Outer.Inner` — the qualified half is what a member would name, and the
        // qualifier is a type in its own right that this rule tracks separately.
        if let member = type.as(MemberTypeSyntax.self) {
            set.insert(member.name.text)
            return
        }
        collectWrappedTypeNames(from: type, into: &set)
    }

    /// The container shapes, split from `collectTypeNames` only to keep each within the
    /// cyclomatic-complexity budget.
    private func collectWrappedTypeNames(from type: TypeSyntax, into set: inout Set<String>) {
        if let optional = type.as(OptionalTypeSyntax.self) {
            collectTypeNames(from: optional.wrappedType, into: &set)
        } else if let array = type.as(ArrayTypeSyntax.self) {
            collectTypeNames(from: array.element, into: &set)
        } else if let dictionary = type.as(DictionaryTypeSyntax.self) {
            collectTypeNames(from: dictionary.key, into: &set)
            collectTypeNames(from: dictionary.value, into: &set)
        } else if let tuple = type.as(TupleTypeSyntax.self) {
            for element in tuple.elements { collectTypeNames(from: element.type, into: &set) }
        }
    }

    private func isSwiftUIApp(_ node: StructDeclSyntax) -> Bool {
        node.inheritanceClause?.inheritedTypes.contains { inherited in
            inherited.type.as(IdentifierTypeSyntax.self)?.name.text == "App"
        } ?? false
    }

    private func hasMainAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName
                .as(IdentifierTypeSyntax.self)?.name.text == "main"
        }
    }

    private func trackProtocolConformance(
        _ name: String,
        inheritance: InheritanceClauseSyntax?
    ) {
        guard let inheritance else { return }
        for inherited in inheritance.inheritedTypes {
            if let ident = inherited.type.as(IdentifierTypeSyntax.self) {
                typeConformances[name, default: []].insert(ident.name.text)
            }
        }
    }

    private func isTopLevel(_ node: Syntax) -> Bool {
        guard let parent = node.parent,
              parent.is(CodeBlockItemSyntax.self),
              let grandparent = parent.parent,
              grandparent.is(CodeBlockItemListSyntax.self),
              let greatGrandparent = grandparent.parent,
              greatGrandparent.is(SourceFileSyntax.self) else { return false }
        return true
    }
}

/// Finds whether a type declaration contains any property-test candidate.
private final class CandidateFunctionCollector: SyntaxVisitor {
    private let knownEquatableTypes: Set<String>

    var foundCandidate = false

    init(knownEquatableTypes: Set<String>, viewMode: SyntaxTreeViewMode) {
        self.knownEquatableTypes = knownEquatableTypes
        super.init(viewMode: viewMode)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if PropertyTestCandidacy.shape(of: node, knownEquatableTypes: knownEquatableTypes) != nil {
            foundCandidate = true
        }
        return .visitChildren
    }
}

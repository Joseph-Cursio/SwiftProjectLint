import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor that reports a layer referencing a type declared in a layer it may not
/// depend on.
///
/// In a single-target app the layers are folders, so no `import` marks a dependency between them:
/// `CheckoutViewModel` in `Presentation/` uses `CoreDataOrderStore` in `Persistence/` by naming it.
/// ``ArchitecturalBoundaryVisitor`` can forbid the frameworks and named types a layer must avoid,
/// but a deny list of project types goes stale with every type added. `may_depend_on` names the
/// layers a layer *may* reference instead, and everything else in another layer is reported.
///
/// **How a reference is attributed.** The rule records the top-level types — structs, classes,
/// enums, actors, protocols and typealiases — each layer's files declare, then finds type
/// annotations and capitalised references to those names in the files of every layer that sets
/// `may_depend_on`. This is syntax, not name resolution, so the rule declines where a name is
/// ambiguous:
/// - A name declared in more than one place — two layers, or a layer and an unlayered file — could
///   be either declaration, so it is not attributed to any layer.
/// - A name the referencing file declares itself, at any depth, is taken to mean its own type.
///
/// A layer without `may_depend_on` is not checked, and files outside every layer are never judged.
/// Each type is reported once per file, at its first reference.
final class LayerDependencyVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// Declarations outside every layer are recorded under this key, so a name they share with a
    /// layer's type still counts as ambiguous.
    private static let unlayered = ""

    func finalizeAnalysis() {
        let policies = layerPolicies
        guard policies.contains(where: { $0.mayDependOn != nil }) else { return }

        let paths = fileCache.keys.sorted()
        var declaringLayers: [String: Set<String>] = [:]
        for path in paths {
            guard let source = fileCache[path] else { continue }
            let layer = LayerPolicy.layer(for: path, in: policies)?.name ?? Self.unlayered
            for name in TopLevelTypeCollector.names(in: source) {
                declaringLayers[name, default: []].insert(layer)
            }
        }

        for path in paths {
            guard let source = fileCache[path],
                  let layer = LayerPolicy.layer(for: path, in: policies),
                  let permitted = layer.mayDependOn else {
                continue
            }
            check(source, at: path, in: layer, permitted: permitted, declaringLayers: declaringLayers)
        }
    }

    private func check(
        _ source: SourceFileSyntax,
        at path: String,
        in layer: LayerPolicy,
        permitted: Set<String>,
        declaringLayers: [String: Set<String>]
    ) {
        let ownNames = AnyDepthTypeCollector.names(in: source)
        var reported: Set<String> = []

        for reference in TypeReferenceCollector.references(in: source) {
            guard ownNames.contains(reference.name) == false,
                  let owners = declaringLayers[reference.name], owners.count == 1,
                  let owner = owners.first, owner != Self.unlayered,
                  owner != layer.name, permitted.contains(owner) == false,
                  reported.contains(reference.name) == false else {
                continue
            }
            reported.insert(reference.name)

            addIssue(
                severity: .warning,
                message: "The '\(layer.name)' layer references '\(reference.name)' from the '\(owner)' layer, "
                    + "which it may not depend on",
                filePath: path,
                lineNumber: getLineNumber(for: reference.node),
                suggestion: "Depend on an abstraction the '\(layer.name)' layer may use, or add '\(owner)' to "
                    + "its may_depend_on if the dependency is intended.",
                ruleName: .layerDependency
            )
        }
    }
}

// MARK: - Collectors

/// The types a file declares at file scope, including inside top-level `#if` blocks.
private final class TopLevelTypeCollector: SyntaxVisitor {
    private(set) var names: [String] = []

    static func names(in source: SourceFileSyntax) -> [String] {
        let collector = TopLevelTypeCollector(viewMode: .sourceAccurate)
        collector.walk(source)
        return collector.names
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }

    // Nothing declared inside these is file scope.
    override func visit(_ _: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ _: FunctionDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ _: VariableDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
        node.item.is(ExprSyntax.self) || node.item.is(StmtSyntax.self) ? .skipChildren : .visitChildren
    }

    private func record(_ name: TokenSyntax) -> SyntaxVisitorContinueKind {
        names.append(name.text)
        return .skipChildren
    }
}

/// Every type name a file declares, at any depth — the names a reference in that file may mean
/// locally rather than in another layer.
private final class AnyDepthTypeCollector: SyntaxVisitor {
    private(set) var names: Set<String> = []

    static func names(in source: SourceFileSyntax) -> Set<String> {
        let collector = AnyDepthTypeCollector(viewMode: .sourceAccurate)
        collector.walk(source)
        return collector.names
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind { record(node.name) }
    override func visit(_ node: GenericParameterSyntax) -> SyntaxVisitorContinueKind { record(node.name) }

    private func record(_ name: TokenSyntax) -> SyntaxVisitorContinueKind {
        names.insert(name.text)
        return .visitChildren
    }
}

/// Type annotations, and capitalised references in expressions — `Order(...)`, `Order.shared` —
/// in source order. A member name after a dot is not a type reference and is skipped.
private final class TypeReferenceCollector: SyntaxVisitor {
    struct Reference {
        let name: String
        let node: Syntax
    }

    private(set) var references: [Reference] = []

    static func references(in source: SourceFileSyntax) -> [Reference] {
        let collector = TypeReferenceCollector(viewMode: .sourceAccurate)
        collector.walk(source)
        return collector.references
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        references.append(Reference(name: node.name.text, node: Syntax(node)))
        return .visitChildren
    }

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        let name = node.baseName.text
        let isMemberName = node.parent?.as(MemberAccessExprSyntax.self)?.declName.id == node.id
        if isMemberName == false, name.first?.isUppercase == true {
            references.append(Reference(name: name, node: Syntax(node)))
        }
        return .visitChildren
    }
}

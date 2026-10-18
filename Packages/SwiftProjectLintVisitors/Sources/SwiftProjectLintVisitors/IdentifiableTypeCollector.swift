import SwiftSyntax

/// A fast SyntaxVisitor that collects the names of all types (struct, class, enum)
/// that declare conformance to `Identifiable` — in their inheritance clause, in an
/// `extension Type: Identifiable`, or, for a class, through SwiftData's `@Model`, which
/// makes it a `PersistentModel` and so `Identifiable`.
///
/// Used as a project-wide pre-scan so that per-file visitors can suppress
/// false-positive "ForEach without ID" warnings when the element type is Identifiable.
public final class IdentifiableTypeCollector: SyntaxVisitor, TypeCollectorProtocol {
    public var collectedTypes: Set<String> { identifiableTypes }

    /// The set of type names found to conform to `Identifiable`.
    private(set) var identifiableTypes: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToIdentifiable(node.inheritanceClause) {
            identifiableTypes.insert(node.name.text)
        }
        return .visitChildren
    }

    override public func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToIdentifiable(node.inheritanceClause) || isSwiftDataModel(node.attributes) {
            identifiableTypes.insert(node.name.text)
        }
        return .visitChildren
    }

    override public func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToIdentifiable(node.inheritanceClause) {
            identifiableTypes.insert(node.name.text)
        }
        return .visitChildren
    }

    override public func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToIdentifiable(node.inheritanceClause),
           let name = node.extendedType.as(IdentifierTypeSyntax.self)?.name.text {
            identifiableTypes.insert(name)
        }
        return .visitChildren
    }

    func isSwiftDataModel(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Model"
        }
    }

    func conformsToIdentifiable(_ clause: InheritanceClauseSyntax?) -> Bool {
        guard let clause else { return false }
        return clause.inheritedTypes.contains { inherited in
            inherited.type.as(IdentifierTypeSyntax.self)?.name.text == "Identifiable"
        }
    }
}

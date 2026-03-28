import SwiftSyntax

/// A fast SyntaxVisitor that collects the names of all types (struct, class, enum)
/// that declare conformance to `Identifiable` in their inheritance clause.
///
/// Used as a project-wide pre-scan so that per-file visitors can suppress
/// false-positive "ForEach without ID" warnings when the element type is Identifiable.
final class IdentifiableTypeCollector: SyntaxVisitor, TypeCollectorProtocol {
    var collectedTypes: Set<String> { identifiableTypes }

    /// The set of type names found to conform to `Identifiable`.
    private(set) var identifiableTypes: Set<String> = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToIdentifiable(node.inheritanceClause) {
            identifiableTypes.insert(node.name.text)
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToIdentifiable(node.inheritanceClause) {
            identifiableTypes.insert(node.name.text)
        }
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToIdentifiable(node.inheritanceClause) {
            identifiableTypes.insert(node.name.text)
        }
        return .visitChildren
    }

    private func conformsToIdentifiable(_ clause: InheritanceClauseSyntax?) -> Bool {
        guard let clause else { return false }
        return clause.inheritedTypes.contains { inherited in
            inherited.type.as(IdentifierTypeSyntax.self)?.name.text == "Identifiable"
        }
    }
}

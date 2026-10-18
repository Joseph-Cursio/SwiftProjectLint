import SwiftSyntax

/// A fast SyntaxVisitor that collects the names of all types (struct, class, enum)
/// that declare conformance to `Identifiable` — in their inheritance clause, in an
/// `extension Type: Identifiable` (`@retroactive` or not), or, for a class, through
/// SwiftData's `@Model`, which makes it a `PersistentModel` and so `Identifiable`.
///
/// A nested type is listed under every name it can be written as: `Entry`, and `Feed.Entry`
/// for an `Entry` declared in `Feed` (or in an `extension Feed`, or conformed through
/// `extension Feed.Entry: Identifiable`). So an unqualified `[Entry]` matches by its leaf name,
/// as it always has, while a qualified `[Other.Entry]` matches only a type declared on that path.
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
            insert(qualifiedPath(of: Syntax(node), name: node.name.text))
        }
        return .visitChildren
    }

    override public func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToIdentifiable(node.inheritanceClause) || isSwiftDataModel(node.attributes) {
            insert(qualifiedPath(of: Syntax(node), name: node.name.text))
        }
        return .visitChildren
    }

    override public func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToIdentifiable(node.inheritanceClause) {
            insert(qualifiedPath(of: Syntax(node), name: node.name.text))
        }
        return .visitChildren
    }

    override public func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsToIdentifiable(node.inheritanceClause),
           let name = qualifiedTypeName(node.extendedType) {
            insert(name)
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
            // `@retroactive Identifiable` is an attributed type around the same name.
            let type = inherited.type.as(AttributedTypeSyntax.self)?.baseType ?? inherited.type
            let name = qualifiedTypeName(type)
            return name == "Identifiable" || name == "Swift.Identifiable"
        }
    }

    /// Inserts `A.B.C` and every shorter suffix of it (`B.C`, `C`): each is how the type is
    /// written from some scope.
    private func insert(_ qualifiedName: String) {
        let components = qualifiedName.split(separator: ".")
        for start in components.indices {
            identifiableTypes.insert(components[start...].joined(separator: "."))
        }
    }

    /// `Feed.Entry` for an `Entry` declared as a member of `Feed` or of an `extension Feed`.
    /// The path stops at anything that is not a type's member block, so a type local to a
    /// function is listed by its own name only.
    private func qualifiedPath(of node: Syntax, name: String) -> String {
        var path = [name]
        var current = node
        while let group = current.parent?.as(MemberBlockItemSyntax.self)?.parent?.parent?.parent {
            if let extensionDecl = group.as(ExtensionDeclSyntax.self) {
                if let extended = qualifiedTypeName(extensionDecl.extendedType) {
                    path.insert(extended, at: 0)
                }
                break
            }
            guard let enclosing = Self.typeName(of: group) else { break }
            path.insert(enclosing, at: 0)
            current = group
        }
        return path.joined(separator: ".")
    }

    private static func typeName(of decl: Syntax) -> String? {
        if let structDecl = decl.as(StructDeclSyntax.self) { return structDecl.name.text }
        if let classDecl = decl.as(ClassDeclSyntax.self) { return classDecl.name.text }
        if let enumDecl = decl.as(EnumDeclSyntax.self) { return enumDecl.name.text }
        if let actorDecl = decl.as(ActorDeclSyntax.self) { return actorDecl.name.text }
        return nil
    }
}

/// `Feed.Entry` for the type `Feed.Entry`, `Item` for `Item` (generic arguments dropped, so
/// `Outer<Int>.Inner` is `Outer.Inner`); `nil` for anything that is not a plain or member type
/// name, such as an array, optional or function type.
func qualifiedTypeName(_ type: TypeSyntax) -> String? {
    // Iterative rather than recursive: a long member chain must not deepen the stack.
    var names: [String] = []
    var current = type
    while let member = current.as(MemberTypeSyntax.self) {
        names.append(member.name.text)
        current = member.baseType
    }
    guard let base = current.as(IdentifierTypeSyntax.self) else { return nil }
    names.append(base.name.text)
    return names.reversed().joined(separator: ".")
}

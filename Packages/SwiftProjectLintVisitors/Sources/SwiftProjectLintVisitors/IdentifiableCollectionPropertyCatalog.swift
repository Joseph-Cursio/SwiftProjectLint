import SwiftSyntax

/// Names of stored or computed properties, declared anywhere in the project, whose type is an
/// array of an `Identifiable` element: `var insights: [Insight]` with `Insight: Identifiable`.
///
/// `ForEach(viewModel.insights)` is fine without `id:` when `Insight` is `Identifiable`, but the
/// per-file ForEach check only sees the view's own file, and `insights` is declared on the view
/// model in another. Matching is by property name alone, so a name is listed only when **every**
/// member property of that name in the project is an array of an `Identifiable` type: one
/// `var history: [String]` anywhere keeps `history` out, and the warning stays.
public enum IdentifiableCollectionPropertyCatalog {

    /// Builds the name set over every parsed source in the project.
    public static func build(from sources: [SourceFileSyntax], identifiable: Set<String>) -> Set<String> {
        let collector = CollectionPropertyCollector(viewMode: .sourceAccurate)
        for source in sources {
            collector.walk(source)
        }
        return resolve(collector.elementTypes, identifiable: identifiable)
    }

    /// The names whose every declaration has a known element type that is `Identifiable`.
    /// A `nil` element type is a declaration the collector could not read (no annotation, or not
    /// an array), and disqualifies its name.
    static func resolve(_ elementTypes: [String: [String?]], identifiable: Set<String>) -> Set<String> {
        Set(elementTypes.compactMap { name, types in
            types.allSatisfy { $0.map(identifiable.contains) ?? false } ? name : nil
        })
    }
}

/// Records, per member property name, the array element type of each declaration of it.
final class CollectionPropertyCollector: SyntaxVisitor {
    private(set) var elementTypes: [String: [String?]] = [:]

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Only members of a type or extension: a local `let insights = …` in some function says
        // nothing about the property a view reads through `viewModel.insights`.
        guard node.parent?.is(MemberBlockItemSyntax.self) == true else {
            return .skipChildren
        }
        for binding in node.bindings {
            guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                continue
            }
            let elementType = binding.typeAnnotation.flatMap { Self.arrayElementType(of: $0.type) }
            elementTypes[name, default: []].append(elementType)
        }
        return .skipChildren
    }

    /// `T` for `[T]` or `Array<T>`, qualified as written (`Feed.Entry` for `[Feed.Entry]`, which
    /// `IdentifiableTypeCollector` lists under that path); `nil` for anything else.
    static func arrayElementType(of type: TypeSyntax) -> String? {
        if let array = type.as(ArrayTypeSyntax.self) {
            return qualifiedTypeName(array.element)
        }
        if let generic = type.as(IdentifierTypeSyntax.self),
           generic.name.text == "Array",
           let argument = generic.genericArgumentClause?.arguments.first,
           generic.genericArgumentClause?.arguments.count == 1 {
            return argument.argument.as(TypeSyntax.self).flatMap(qualifiedTypeName)
        }
        return nil
    }
}

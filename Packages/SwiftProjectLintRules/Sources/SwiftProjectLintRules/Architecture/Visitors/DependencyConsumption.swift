import SwiftSyntax

/// Shared structural detector for "this type consumes X as an injected dependency" —
/// the signal that exempts a single-conformer or mirror protocol that is a deliberate
/// dependency-injection seam. Kept in one place so `SingleImplementationProtocol` and
/// `MirrorProtocol` cannot drift on what counts as dependency injection (the same
/// reason `ProtocolExemption` centralises the mock/DI-suffix predicates).
///
/// A dependency is *consumed* when a type **holds** it (a stored instance property) or
/// **receives** it (an initializer parameter — constructor injection). Method
/// parameters and return types are intentionally excluded: they are not held
/// dependencies, so the exemption stays narrow and the rule still fires on a protocol
/// that is merely mentioned in passing.
enum DependencyConsumption {

    /// The base type names consumed as dependencies by the members of one type
    /// declaration (or extension). Callers union these across every declaration walked,
    /// then exempt a protocol whose name appears in the accumulated set.
    static func consumedTypeNames(in members: MemberBlockSyntax) -> Set<String> {
        var names: Set<String> = []
        for member in members.members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self),
               isStoredInstanceProperty(varDecl) {
                for binding in varDecl.bindings {
                    if let type = binding.typeAnnotation?.type,
                       let name = baseTypeName(type) {
                        names.insert(name)
                    }
                }
            } else if let initDecl = member.decl.as(InitializerDeclSyntax.self) {
                for parameter in initDecl.signature.parameterClause.parameters {
                    if let name = baseTypeName(parameter.type) {
                        names.insert(name)
                    }
                }
            }
        }
        return names
    }

    /// Stored, instance-level, non-computed property. `static`/`class`/`lazy` and
    /// computed properties are not dependency-holding instance state.
    private static func isStoredInstanceProperty(_ varDecl: VariableDeclSyntax) -> Bool {
        for modifier in varDecl.modifiers
        where ["static", "class", "lazy"].contains(modifier.name.text) {
            return false
        }
        for binding in varDecl.bindings where binding.accessorBlock != nil {
            return false
        }
        return true
    }

    /// The base type name of a dependency annotation, unwrapping `any`/`some`,
    /// optionals, and a single array layer (`[any P]` — plugin-list injection) so the
    /// existential `any DataParsing` and the bare `DataParsing` both resolve to
    /// `DataParsing`. Returns `nil` for tuples, functions, and other non-nominal types.
    private static func baseTypeName(_ type: TypeSyntax) -> String? {
        if let someOrAny = type.as(SomeOrAnyTypeSyntax.self) {
            return baseTypeName(someOrAny.constraint)
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return baseTypeName(optional.wrappedType)
        }
        if let implicit = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return baseTypeName(implicit.wrappedType)
        }
        if let array = type.as(ArrayTypeSyntax.self) {
            return baseTypeName(array.element)
        }
        if let ident = type.as(IdentifierTypeSyntax.self) {
            if ident.name.text == "Optional",
               let inner = ident.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self) {
                return baseTypeName(inner)
            }
            return ident.name.text
        }
        return nil
    }
}

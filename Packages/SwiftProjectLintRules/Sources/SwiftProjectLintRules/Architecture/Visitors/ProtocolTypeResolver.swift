import SwiftSyntax

/// Generic parameters in scope, innermost last: `T` → the protocols it is constrained to.
///
/// An unconstrained parameter maps to an empty set, which still matters — a generic parameter
/// named like a protocol shadows it.
struct GenericScope {
    private var frames: [[String: Set<String>]] = []

    func lookup(_ name: String) -> Set<String>? {
        for frame in frames.reversed() {
            if let protocols = frame[name] {
                return protocols
            }
        }
        return nil
    }

    mutating func push(_ frame: [String: Set<String>]) {
        frames.append(frame)
    }

    mutating func pop() {
        frames.removeLast()
    }
}

/// Resolves a written type to the project protocols a value of it is typed with.
///
/// Name resolution only: a generic parameter in scope, then a project protocol, then a project
/// typealias. The wrappers it looks through are the ones `ProtocolTypePosition` treats as
/// transparent, and the two must agree — a binding the classifier calls followable but this
/// resolver cannot read would be a client nobody tracks.
struct ProtocolTypeResolver {
    let declarations: ProtocolDeclarations
    private let ancestorCache: [String: Set<String>]

    init(declarations: ProtocolDeclarations) {
        self.declarations = declarations
        var cache: [String: Set<String>] = [:]
        for name in declarations.protocols.keys {
            cache[name] = declarations.ancestors(of: name)
        }
        ancestorCache = cache
    }

    /// Protocols (closed over refinement) a value of `type` is typed with. Empty when the type
    /// is not one the index follows: a concrete type, `[any P]`, a function type.
    func protocols(in type: TypeSyntax, generics: GenericScope, depth: Int = 0) -> Set<String> {
        guard depth < 8 else { return [] }
        if let unwrapped = transparentlyWrapped(type) {
            return protocols(in: unwrapped, generics: generics, depth: depth + 1)
        }
        if let composition = type.as(CompositionTypeSyntax.self) {
            return composition.elements.reduce(into: Set<String>()) { result, element in
                result.formUnion(protocols(in: element.type, generics: generics, depth: depth + 1))
            }
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            if identifier.name.text == "Optional", let wrapped = singleGenericArgument(of: identifier) {
                return protocols(in: wrapped, generics: generics, depth: depth + 1)
            }
            return protocols(named: identifier.name.text, generics: generics, depth: depth) ?? []
        }
        if let member = type.as(MemberTypeSyntax.self) {
            // `Module.P` — a qualified protocol name. Never a generic parameter.
            return protocols(named: member.name.text, generics: GenericScope(), depth: depth) ?? []
        }
        return []
    }

    /// What one type name means: the protocols of a generic parameter in scope, a protocol (with
    /// the protocols it refines), or the protocols an alias composes. `nil` for any other name.
    func protocols(named name: String, generics: GenericScope, depth: Int = 0) -> Set<String>? {
        if let constrained = generics.lookup(name) {
            return constrained
        }
        if let ancestors = ancestorCache[name] {
            return ancestors
        }
        guard let alias = declarations.aliases[name], depth < 8 else { return nil }
        let resolved = protocols(in: alias, generics: GenericScope(), depth: depth + 1)
        return resolved.isEmpty ? nil : resolved
    }

    /// The generic parameters a clause declares, with the protocols each is constrained to by
    /// the clause or by a `where T: P` requirement.
    func genericFrame(
        parameters: GenericParameterClauseSyntax?,
        whereClause: GenericWhereClauseSyntax?,
        outer: GenericScope
    ) -> [String: Set<String>] {
        var frame: [String: Set<String>] = [:]
        for parameter in parameters?.parameters ?? [] {
            let name = parameter.name.text
            frame[name] = parameter.inheritedType.map { protocols(in: $0, generics: outer) } ?? []
        }
        var scope = outer
        scope.push(frame)
        for requirement in whereClause?.requirements ?? [] {
            guard let conformance = requirement.requirement.as(ConformanceRequirementSyntax.self),
                  let constrained = conformance.leftType.as(IdentifierTypeSyntax.self) else {
                continue
            }
            let name = constrained.name.text
            let added = protocols(in: conformance.rightType, generics: scope)
            if frame[name] != nil || scope.lookup(name) != nil {
                frame[name, default: scope.lookup(name) ?? []].formUnion(added)
            }
        }
        return frame
    }

    // MARK: - Wrappers

    /// `any P`, `some P`, `P?`, `P!`, `@Sendable P`, `inout P` and `(P)` are all `P`.
    private func transparentlyWrapped(_ type: TypeSyntax) -> TypeSyntax? {
        if let someOrAny = type.as(SomeOrAnyTypeSyntax.self) {
            return someOrAny.constraint
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return optional.wrappedType
        }
        if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return unwrapped.wrappedType
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return attributed.baseType
        }
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
           let element = tuple.elements.first, element.firstName == nil {
            return element.type
        }
        return nil
    }

    private func singleGenericArgument(of identifier: IdentifierTypeSyntax) -> TypeSyntax? {
        guard let arguments = identifier.genericArgumentClause?.arguments, arguments.count == 1,
              case .type(let type) = arguments.first?.argument else {
            return nil
        }
        return type
    }
}

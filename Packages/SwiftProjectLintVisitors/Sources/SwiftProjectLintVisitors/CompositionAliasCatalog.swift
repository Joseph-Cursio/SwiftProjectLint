import SwiftSyntax

/// `typealias` declarations that stand for other named types and nothing else: a protocol
/// composition (`typealias OrderStore = OrderSaving & OrderHistory`), an existential
/// (`typealias AnyStore = any OrderSaving`), or a plain rename (`typealias Legacy = Renamed`).
/// Each one is resolved to the names it stands for.
///
/// ## Why this exists
///
/// An inheritance clause may name such an alias, and the conformance it declares is a
/// conformance to every component. `actor CoreDataOrderStore: OrderStore` conforms to
/// `OrderSaving` and `OrderHistory` exactly as `actor CoreDataOrderStore: OrderSaving,
/// OrderHistory` does. It is how the standard library defines `Codable`.
///
/// The rules that count conformances by name read `OrderStore`, which is not a protocol, so the
/// store's real conformances disappeared. Found on Checkout's `solid/i-split-store`: written
/// through the alias, `Single Implementation Protocol` reported every role as having *no*
/// conformers; written out, it reported the right one. `expand(_:)` is the one place that
/// knowledge lives, so every rule reading an inheritance clause gets the same answer.
///
/// ## What is resolved, and what is left alone
///
/// - **Transitively.** A component that is itself a catalogued alias expands into that alias's
///   components, so `typealias Store = Reading & Writing` with `typealias Reading = A & B`
///   stands for `A`, `B` and `Writing`.
/// - **Only shapes a conformance can name.** A non-generic alias whose right-hand side is built
///   from bare names, `&` and `any`. A function type, a generic argument, an optional or a
///   qualified `Module.Name` is not catalogued.
/// - **Not when the name is ambiguous.** A name declared as an alias with two different
///   right-hand sides (a nested `typealias Element` in several types), or declared as a type,
///   an associated type or a generic parameter as well, is left unexpanded. A rule sees only the
///   name, so it cannot tell which declaration a given use means, and leaving the name alone is
///   what every rule did before this catalog existed.
/// - **Not a cycle.** `typealias A = B` with `typealias B = A` is rejected by the compiler; both
///   are dropped.
public struct CompositionAliasCatalog: Sendable, Equatable {

    /// Alias name → the names it stands for, fully resolved, in source order, without repeats.
    private let components: [String: [String]]

    /// Aliases written with `&` or `any` somewhere along their chain: existentials, whatever
    /// their components are.
    private let existentials: Set<String>

    /// The catalog a caller with no source to build from gets: nothing is an alias, so every
    /// name expands to itself and behaviour matches the rules as they were before it existed.
    public static let empty = Self(components: [:], existentials: [])

    init(components: [String: [String]], existentials: Set<String>) {
        self.components = components
        self.existentials = existentials
    }

    /// The names `name` stands for when it appears in an inheritance clause or a type position:
    /// the alias's components, or `name` itself when it is not a catalogued alias.
    public func expand(_ name: String) -> [String] {
        components[name] ?? [name]
    }

    /// Whether `name` is a catalogued alias.
    public func isAlias(_ name: String) -> Bool {
        components[name] != nil
    }

    public var isEmpty: Bool { components.isEmpty }

    /// The aliases that name an abstraction rather than a concrete type: every existential,
    /// plus every alias that stands only for protocols in `protocols`.
    ///
    /// `typealias OrderStore = OrderSaving & OrderHistory` qualifies by its `&`, which can only
    /// compose protocols (and at most one class). `typealias Store = OrderSaving` qualifies
    /// because `OrderSaving` is a protocol. `typealias Model = UserRecord` does not.
    public func abstractionAliases(protocols: Set<String>) -> Set<String> {
        Set(components.compactMap { name, names in
            existentials.contains(name) || names.allSatisfy(protocols.contains) ? name : nil
        })
    }

    /// Builds the catalog over every parsed source in the project.
    public static func build(from sources: [SourceFileSyntax]) -> Self {
        let collector = CompositionAliasCollector(viewMode: .sourceAccurate)
        for source in sources {
            collector.walk(source)
        }
        return resolve(collector.definitions, excluding: collector.otherDeclaredNames)
    }

    /// What one `typealias` says, before any of its components are themselves expanded.
    struct Definition: Equatable {
        let names: [String]
        let isExistential: Bool
    }

    /// Resolves each unambiguous alias through any aliases among its components.
    static func resolve(
        _ definitions: [String: [Definition]],
        excluding otherDeclaredNames: Set<String>
    ) -> Self {
        var unambiguous: [String: Definition] = [:]
        for (name, candidates) in definitions where !otherDeclaredNames.contains(name) {
            guard let first = candidates.first,
                  candidates.allSatisfy({ $0 == first }) else { continue }
            unambiguous[name] = first
        }

        var resolver = Resolver(definitions: unambiguous)
        var components: [String: [String]] = [:]
        var existentials: Set<String> = []
        for name in unambiguous.keys {
            guard let resolved = resolver.resolve(name) else { continue }
            components[name] = resolved.names
            if resolved.isExistential { existentials.insert(name) }
        }
        return Self(components: components, existentials: existentials)
    }

    /// Memoised, cycle-checked expansion of one alias at a time.
    private struct Resolver {
        let definitions: [String: Definition]
        /// `nil` records an alias that could not be resolved, so a cycle is reported once.
        private var memo: [String: Definition?] = [:]
        private var inProgress: Set<String> = []

        init(definitions: [String: Definition]) {
            self.definitions = definitions
        }

        mutating func resolve(_ name: String) -> Definition? {
            if let known = memo[name] { return known }
            guard let definition = definitions[name] else { return nil }
            // Reaching an alias that is still being resolved means the chain leads back to
            // itself. The compiler rejects that, so neither end is trusted.
            guard inProgress.insert(name).inserted else { return nil }
            defer { inProgress.remove(name) }

            var names: [String] = []
            var isExistential = definition.isExistential
            for component in definition.names {
                guard definitions[component] != nil else {
                    names.append(component)
                    continue
                }
                guard let inner = resolve(component) else {
                    memo[name] = .some(nil)
                    return nil
                }
                names.append(contentsOf: inner.names)
                isExistential = isExistential || inner.isExistential
            }

            var seen: Set<String> = []
            let result = Definition(
                names: names.filter { seen.insert($0).inserted },
                isExistential: isExistential
            )
            memo[name] = result
            return result
        }
    }
}

/// Walks the sources for ``CompositionAliasCatalog``: every alias definition it could
/// catalogue, and every name declared some other way that would make an alias name ambiguous.
final class CompositionAliasCollector: SyntaxVisitor {

    private(set) var definitions: [String: [CompositionAliasCatalog.Definition]] = [:]
    private(set) var otherDeclaredNames: Set<String> = []

    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        // A generic alias is a type constructor; a conformance cannot name it bare.
        guard node.genericParameterClause == nil else {
            otherDeclaredNames.insert(node.name.text)
            return .visitChildren
        }
        guard let definition = Self.definition(of: node.initializer.value) else {
            // Declared, but not as anything this catalog can expand. It still shares the name.
            otherDeclaredNames.insert(node.name.text)
            return .visitChildren
        }
        definitions[node.name.text, default: []].append(definition)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        otherDeclaredNames.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        otherDeclaredNames.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        otherDeclaredNames.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        otherDeclaredNames.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        otherDeclaredNames.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: AssociatedTypeDeclSyntax) -> SyntaxVisitorContinueKind {
        otherDeclaredNames.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: GenericParameterSyntax) -> SyntaxVisitorContinueKind {
        otherDeclaredNames.insert(node.name.text)
        return .visitChildren
    }

    /// The names an alias's right-hand side is built from, or `nil` when it is built from
    /// anything else.
    static func definition(of type: TypeSyntax) -> CompositionAliasCatalog.Definition? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            guard identifier.genericArgumentClause == nil else { return nil }
            return .init(names: [identifier.name.text], isExistential: false)
        }
        if let composition = type.as(CompositionTypeSyntax.self) {
            var names: [String] = []
            for element in composition.elements {
                guard let part = definition(of: element.type) else { return nil }
                names.append(contentsOf: part.names)
            }
            return .init(names: names, isExistential: true)
        }
        if let existential = type.as(SomeOrAnyTypeSyntax.self),
           existential.someOrAnySpecifier.tokenKind == .keyword(.any),
           let inner = definition(of: existential.constraint) {
            return .init(names: inner.names, isExistential: true)
        }
        return nil
    }
}

import SwiftSyntax

/// Who depends on each project protocol, and which of its members they reach *through* it.
///
/// A **client** is anything that holds or produces a value whose static type is the protocol: a
/// stored property, parameter or local typed `P`, `any P`, `some P` or `T` where `T: P`; a function
/// returning `P`; a cast to `P`; a member of `extension P`, whose `self` is the protocol. Each
/// client records the members called on it, and whether its value escaped somewhere this local,
/// name-based resolution cannot follow — after which it is assumed to use every requirement.
///
/// The uses are kept **per client** rather than merged. `UnusedProtocolRequirement` asks the
/// union question — which requirements does no client use — and splitting a protocol into the
/// groups its clients actually use (stage 2 of use-based interface segregation) asks the
/// per-client one from the same data.
///
/// Built in three passes over the run's parsed files:
/// 1. `ProtocolDeclarationScan` — protocols, typealiases, type names, generics, supertypes.
/// 2. `ProtocolMemberScan` — members, callables and producers, which need (1) to resolve types.
/// 3. `ProtocolClientWalker` — bodies: parameters and locals, member calls, escapes.
struct ProtocolClientIndex {
    /// Project protocols by name. A name declared twice (two `private` protocols in different
    /// files) keeps both, and their clients are shared — over-crediting, the safe direction.
    var protocols: [String: [ProtocolInfo]] = [:]
    var clients: [ProtocolClient] = []
    /// Protocols a value of which reaches a position this index cannot follow (`[any P]`,
    /// `Box<any P>`, `P.self`, an enum payload), each with the first such position as
    /// `file:line`. Every requirement of such a protocol is in use.
    var opaqueSites: [String: String] = [:]
    /// Every base name referenced by an expression in the run. A member of `extension P` is
    /// live — its calls count — when its name is referenced anywhere.
    var referencedNames: Set<String> = []

    /// Builds the index from every file of the run, in a fixed order.
    static func build(from sources: [(path: String, tree: SourceFileSyntax)]) -> Self {
        var index = Self()
        let declarations = ProtocolDeclarationScan.scan(sources)
        index.protocols = declarations.protocols
        var members = ProtocolMemberScan(declarations: declarations)
        for source in sources {
            members.scan(source.tree, path: source.path)
        }
        members.resolveInferredMembers()
        index.clients = members.clients
        for source in sources {
            let walker = ProtocolClientWalker(
                members: members, clients: index.clients, filePath: source.path, tree: source.tree
            )
            walker.walk(source.tree)
            index.clients = walker.clients
            index.opaqueSites.merge(walker.opaqueSites) { first, _ in first }
            index.referencedNames.formUnion(walker.referencedNames)
        }
        return index
    }

    /// The clients through which `protocolName` is used: every client typed with it or with a
    /// protocol refining it, and every referenced member of an extension of either.
    func liveClients(of protocolName: String) -> [ProtocolClient] {
        clients.filter { client in
            guard client.protocols.contains(protocolName) else { return false }
            guard let trigger = client.liveWhenReferenced else { return true }
            return referencedNames.contains(trigger)
        }
    }
}

// MARK: - Model

/// A protocol declared in the run's sources.
struct ProtocolInfo {
    let name: String
    let filePath: String
    let line: Int
    let requirements: [ProtocolRequirement]
    /// Every name in the inheritance clause, project protocols and framework ones alike.
    let inheritedNames: [String]
    let modifiers: Set<String>
    let attributeNames: [String]
}

/// One requirement of a protocol, keyed the way a call site can be matched against it.
struct ProtocolRequirement: Hashable {
    enum Kind {
        case method
        case property
        case subscriptMember
        case initializer
        case associatedType
    }

    let kind: Kind
    /// The base name: `save` for `save(_:)`.
    let name: String
    /// External argument labels, `_` for an unlabelled parameter. Empty for a property.
    let labels: [String]
    let isStatic: Bool
    let hasVariadicParameter: Bool
    let line: Int

    /// `save(_:)`, `order(withIdentifier:)`, `recentOrders()`, `title`.
    var displayName: String {
        switch kind {
        case .method:
            return "\(name)(\(labels.map { "\($0):" }.joined()))"

        case .subscriptMember:
            return "subscript(\(labels.map { "\($0):" }.joined()))"

        case .property, .initializer, .associatedType:
            return name
        }
    }
}

/// A member reached through a protocol-typed value: `store.save(order)` records
/// `save` with labels `["_"]`.
struct MemberUse: Hashable {
    let name: String
    /// The call's argument labels — `_` for an unlabelled argument, `nil` for a trailing closure,
    /// whose label the call site does not spell. `nil` when the member is not called: a property
    /// read or write, or an unapplied method reference.
    let labels: [String?]?

    /// Matching is by base name plus labels — local name resolution, not overload resolution.
    func matches(_ requirement: ProtocolRequirement) -> Bool {
        switch requirement.kind {
        case .property:
            return name == requirement.name

        case .subscriptMember:
            return name == "subscript"

        case .method:
            guard name == requirement.name else { return false }
            guard let labels, requirement.hasVariadicParameter == false else { return true }
            guard labels.count == requirement.labels.count else { return false }
            return zip(labels, requirement.labels).allSatisfy { $0 == nil || $0 == $1 }

        case .initializer, .associatedType:
            return false
        }
    }
}

/// A declaration or expression through which a protocol-typed value is used.
struct ProtocolClient {
    enum Kind {
        case property
        case parameter
        case local
        case producer
        case cast
        case construction
        case extensionMember
    }

    let kind: Kind
    /// Readable name: `CheckoutViewModel.store`, `placeOrder(_:) parameter 'store'`.
    let name: String
    /// The protocols the value is typed with, closed over refinement: a client typed `Q`,
    /// where `protocol Q: P`, is a client of both.
    let protocols: Set<String>
    let filePath: String
    let line: Int
    /// For a member of `extension P`: the name whose being referenced makes it count.
    let liveWhenReferenced: String?
    var uses: Set<MemberUse> = []
    /// Where the value first went somewhere untracked, as `file:line`. From then on it may
    /// reach any requirement.
    var escapeSite: String?

    var escapes: Bool {
        escapeSite != nil
    }
}

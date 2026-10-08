import SwiftSyntax

/// What a name in scope refers to, as far as the index is concerned.
enum ProtocolBinding: Equatable {
    /// A protocol-typed value: these clients receive whatever is called on it.
    case clients(Set<Int>)
    /// Anything else. Recorded so that a local can shadow a protocol-typed member.
    case other
}

/// A callable's parameters, for following a protocol-typed argument one hop into its callee.
struct CallableSignature {
    struct Parameter {
        /// The external label, `_` when there is none.
        let label: String
        /// Empty when the parameter is not protocol-typed.
        let protocols: Set<String>
    }

    let parameters: [Parameter]

    /// The parameter an argument binds to: by label, and for unlabelled arguments by their
    /// position among the unlabelled parameters.
    func parameter(label: String, unlabeledIndex: Int) -> Parameter? {
        guard label == "_" else {
            return parameters.first { $0.label == label }
        }
        let unlabeled = parameters.filter { $0.label == "_" }
        return unlabeled.indices.contains(unlabeledIndex) ? unlabeled[unlabeledIndex] : nil
    }
}

/// Pass two of `ProtocolClientIndex`: every declaration that is visible by name from elsewhere —
/// properties, functions, initializers, protocol-extension members — resolved against the
/// protocols pass one found.
struct ProtocolMemberScan {
    let declarations: ProtocolDeclarations
    let resolver: ProtocolTypeResolver
    var clients: [ProtocolClient] = []
    /// Type name → property name → what it is. Includes protocol requirement properties.
    var typeMembers: [String: [String: ProtocolBinding]] = [:]
    /// Property name → every protocol-typed property of that name, on any type. `x.store` is
    /// resolved by name, since `x` is not typed.
    var memberClientsByName: [String: Set<Int>] = [:]
    var globals: [String: ProtocolBinding] = [:]
    var callables: [String: [CallableSignature]] = [:]
    /// Type name → its initializers, including a struct's memberwise one.
    var initializers: [String: [CallableSignature]] = [:]
    /// Function name → the producer clients of every function of that name returning a protocol.
    var producers: [String: Set<Int>] = [:]
    /// Each member of a protocol extension → its client, whose `self` is the protocol.
    var extensionMembers: [SyntaxIdentifier: Int] = [:]
    private var genericFrames: [String: [String: Set<String>]] = [:]
    var pendingInferred: [PendingInferredMember] = []

    init(declarations: ProtocolDeclarations) {
        self.declarations = declarations
        resolver = ProtocolTypeResolver(declarations: declarations)
    }

    mutating func scan(_ tree: SourceFileSyntax, path: String) {
        let collector = ProtocolMemberCollector(
            scan: self,
            filePath: path,
            converter: SourceLocationConverter(fileName: path, tree: tree)
        )
        collector.walk(tree)
        self = collector.scan
    }

    // MARK: - Queries

    /// The generic parameters a nominal type declares, resolved.
    mutating func genericFrame(ofType name: String) -> [String: Set<String>] {
        if let cached = genericFrames[name] {
            return cached
        }
        var frame: [String: Set<String>] = [:]
        for clause in declarations.genericClauses[name] ?? [] {
            let resolved = resolver.genericFrame(
                parameters: clause.parameters, whereClause: clause.whereClause, outer: GenericScope()
            )
            frame.merge(resolved) { $0.union($1) }
        }
        genericFrames[name] = frame
        return frame
    }

    /// A member of `typeName` or of anything it inherits from, by name.
    func member(named name: String, in typeName: String) -> ProtocolBinding? {
        var visited: Set<String> = []
        var pending = [typeName]
        while let next = pending.popLast() {
            guard visited.insert(next).inserted else { continue }
            if let binding = typeMembers[next]?[name] {
                return binding
            }
            pending.append(contentsOf: declarations.supertypes[next] ?? [])
            pending.append(contentsOf: declarations.protocols[next]?.flatMap(\.inheritedNames) ?? [])
        }
        return nil
    }

    // MARK: - Building

    mutating func addClient(_ client: ProtocolClient) -> Int {
        clients.append(client)
        return clients.count - 1
    }

    mutating func recordMember(_ name: String, in typeName: String?, binding: ProtocolBinding) {
        if let typeName {
            typeMembers[typeName, default: [:]][name] = binding
        } else {
            globals[name] = binding
        }
        if case .clients(let identifiers) = binding {
            memberClientsByName[name, default: []].formUnion(identifiers)
        }
    }

    /// Settles the properties declared without a type: `let store = makeStore()`,
    /// `@Environment(\.orderStore) var store`. They need every producer and typed member first.
    mutating func resolveInferredMembers() {
        let pending = pendingInferred
        pendingInferred = []
        for member in pending {
            recordMember(member.name, in: member.typeName, binding: inferredBinding(of: member))
        }
    }

    private mutating func inferredBinding(of member: PendingInferredMember) -> ProtocolBinding {
        if let keyPathName = member.keyPathMemberName {
            return memberClientsByName[keyPathName].map(ProtocolBinding.clients) ?? .other
        }
        guard let initializer = member.initializer else { return .other }
        let value = ProtocolValueShape.peel(initializer)
        if let callee = ProtocolValueShape.calleeName(of: value), let produced = producers[callee] {
            return .clients(produced)
        }
        if let access = value.as(MemberAccessExprSyntax.self),
           let named = memberClientsByName[access.declName.baseName.text] {
            return .clients(named)
        }
        if let cast = ProtocolValueShape.castTarget(of: value) {
            let protocols = resolver.protocols(in: cast, generics: GenericScope())
            guard protocols.isEmpty == false else { return .other }
            let identifier = addClient(ProtocolClient(
                kind: .cast, name: "\(member.displayName) (cast)", protocols: protocols,
                filePath: member.filePath, line: member.line, liveWhenReferenced: nil
            ))
            return .clients([identifier])
        }
        return .other
    }
}

/// A property declared without a type annotation, settled after every file is scanned.
struct PendingInferredMember {
    let name: String
    let typeName: String?
    let initializer: ExprSyntax?
    /// `store` for `@Environment(\.store) var …` — the key path's last component.
    let keyPathMemberName: String?
    let filePath: String
    let line: Int

    var displayName: String {
        typeName.map { "\($0).\(name)" } ?? name
    }
}

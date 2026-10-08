import SwiftSyntax

/// The project's actors, and for each one the project protocols it already conforms to that a
/// caller can reach only through `await`.
///
/// Built once in the pre-scan, because the three facts it joins are rarely in one file: the actor
/// is declared in one, the protocol in another, and the conformance is as often an
/// `extension Actor: Protocol {}` in a third.
///
/// ## Why an actor is exempt from `Concrete Type Usage` — and when it stops being
///
/// An actor's isolation is a contract the compiler enforces at every call site: from outside, a
/// caller must `await`, and access is serialised on the actor's executor. A protocol in front of
/// an actor *can* drop that — a synchronous requirement can only be satisfied by a `nonisolated`
/// member, or by a `@preconcurrency` conformance that defers the check to run time — so an actor
/// with no protocol around it keeps the exemption, and so does one whose protocols all have a
/// synchronous requirement.
///
/// A project protocol whose every instance requirement is `async` cannot drop it. Callers going
/// through it still `await`, and the conformance cannot weaken that silently: Swift 6 rejects an
/// actor-isolated member satisfying a synchronous requirement, because the conformance *"crosses
/// into actor-isolated code and can cause data races"*. When such a protocol exists, the actor has
/// already been abstracted with nothing lost, and a property or parameter naming the actor instead
/// is exactly the coupling the rule reports.
///
/// ## What counts as an all-`async` protocol
///
/// Declared in the analysed sources, not `private` or `fileprivate` (a caller in another file
/// could not name it), with at least one `async` instance requirement and no synchronous one,
/// counting every requirement it inherits from other project protocols. `init`, `static`
/// members and associated types are never isolated to an instance, so they neither qualify a
/// protocol nor disqualify it. A parent outside the project counts as synchronous — its
/// requirements are not visible here — unless it is one of the marker protocols that carry none.
///
/// The actor's conformances are its inheritance clause and every `extension` of it, widened to
/// the project protocols those inherit from: an actor conforming to `RichStore: OrderStore`
/// conforms to `OrderStore` too, and can be typed as it. A composition `typealias` in either
/// place stands for the protocols it composes (see `CompositionAliasCatalog`):
/// `actor CoreDataOrderStore: OrderStore`, with `typealias OrderStore = OrderSaving &
/// OrderHistory`, conforms to both roles.
public struct ActorTypeCatalog: Sendable, Equatable {

    private let actors: Set<String>
    private let asyncProtocolsByActor: [String: [String]]

    /// The catalog a caller with no pre-scan gets: nothing is an actor, so behaviour matches a
    /// run that never looked.
    public static let empty = Self(actors: [])

    public init(actors: Set<String>, asyncProtocolsByActor: [String: [String]] = [:]) {
        self.actors = actors
        self.asyncProtocolsByActor = asyncProtocolsByActor
    }

    /// Whether `name` is declared as an actor anywhere in the project.
    public func contains(_ name: String) -> Bool { actors.contains(name) }

    /// The all-`async` project protocols `name` conforms to, sorted; empty when there are none or
    /// `name` is not an actor.
    public func asyncProtocols(conformedToBy name: String) -> [String] {
        asyncProtocolsByActor[name] ?? []
    }

    /// Builds the catalog over every parsed source in the project, reading a conformance written
    /// through one of `aliases` as a conformance to each protocol it composes.
    public static func build(
        from sources: [SourceFileSyntax],
        aliases: CompositionAliasCatalog = .empty
    ) -> Self {
        let collector = ActorTypeCollector()
        for source in sources {
            collector.walk(source)
        }
        return collector.resolved(aliases: aliases)
    }
}

/// Walks the project for the three facts ``ActorTypeCatalog`` joins: actor names, every type's
/// declared conformances, and each protocol's requirement shape.
public final class ActorTypeCollector: SyntaxVisitor {

    private var actors: Set<String> = []

    /// Every type's declared conformances, inline and from `extension`s. Recorded for every type
    /// because an extension does not say whether it extends an actor; resolution keeps the actors.
    private var conformances: [String: Set<String>] = [:]

    private var protocols: [String: ProtocolIsolationShape] = [:]

    /// The project's composition aliases, set when resolving. A protocol may refine one
    /// (`protocol RichStore: OrderStore`), and an unexpanded alias would read as a parent this run
    /// cannot see — synchronous by assumption.
    private var aliases = CompositionAliasCatalog.empty

    /// Parents outside the project that add no requirement an actor's isolation could leak
    /// through. `Actor`'s one requirement, `unownedExecutor`, is `nonisolated` and synthesised.
    private static let requirementFreeParents: Set<String> = [
        "Sendable", "AnyObject", "Actor", "AnyActor", "SendableMetatype",
        "Copyable", "Escapable", "BitwiseCopyable"
    ]

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        actors.insert(node.name.text)
        conformances[node.name.text, default: []].formUnion(Self.names(in: node.inheritanceClause))
        return .visitChildren
    }

    override public func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let name = Self.names(of: node.extendedType).last {
            conformances[name, default: []].formUnion(Self.names(in: node.inheritanceClause))
        }
        return .visitChildren
    }

    override public func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        protocols[node.name.text, default: ProtocolIsolationShape()].merge(.reading(node))
        // A protocol cannot nest a type, so nothing below it is an actor or a conformance.
        return .skipChildren
    }

    func resolved(aliases: CompositionAliasCatalog = .empty) -> ActorTypeCatalog {
        self.aliases = aliases
        var asyncProtocolsByActor: [String: [String]] = [:]
        for actor in actors {
            let reachable = (conformances[actor] ?? []).reduce(into: Set<String>()) { found, name in
                for protocolName in aliases.expand(name) {
                    collectAncestors(of: protocolName, into: &found)
                }
            }
            let qualifying = reachable.filter(isAllAsync).sorted()
            if !qualifying.isEmpty {
                asyncProtocolsByActor[actor] = qualifying
            }
        }
        return ActorTypeCatalog(actors: actors, asyncProtocolsByActor: asyncProtocolsByActor)
    }

    /// `name` and every project protocol it inherits from, transitively.
    private func collectAncestors(of name: String, into found: inout Set<String>) {
        guard let shape = protocols[name], found.insert(name).inserted else { return }
        for parent in shape.inherited.flatMap(aliases.expand) {
            collectAncestors(of: parent, into: &found)
        }
    }

    private func isAllAsync(_ name: String) -> Bool {
        guard let shape = protocols[name], !shape.isFileLocal else { return false }
        var visited: Set<String> = []
        let reach = requirements(of: name, visited: &visited)
        return reach.hasAwaited && !reach.hasSynchronous
    }

    /// The requirement kinds `name` carries, its own and inherited. One traversal ORs every node
    /// once, so a diamond's shared ancestor or a cycle contributes the first time it is reached.
    private func requirements(of name: String, visited: inout Set<String>) -> ProtocolIsolationShape {
        if Self.requirementFreeParents.contains(name) { return ProtocolIsolationShape() }
        guard let shape = protocols[name] else {
            // A parent this run cannot see: its requirements may be synchronous, so assume so.
            var unseen = ProtocolIsolationShape()
            unseen.hasSynchronous = true
            return unseen
        }
        guard visited.insert(name).inserted else { return ProtocolIsolationShape() }
        var total = shape
        for parent in shape.inherited.flatMap(aliases.expand) {
            total.merge(requirements(of: parent, visited: &visited))
        }
        return total
    }

    // MARK: - Names

    /// The protocol names an inheritance clause lists.
    static func names(in clause: InheritanceClauseSyntax?) -> Set<String> {
        Set(clause?.inheritedTypes.flatMap { names(of: $0.type) } ?? [])
    }

    /// The simple names a type spells: `Domain.OrderStore` → `OrderStore`,
    /// `@preconcurrency OrderStore` → `OrderStore`, `A & B` → both. `~Copyable` names nothing.
    static func names(of type: TypeSyntax) -> [String] {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return [identifier.name.text]
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return [member.name.text]
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return names(of: attributed.baseType)
        }
        if let composition = type.as(CompositionTypeSyntax.self) {
            return composition.elements.flatMap { names(of: $0.type) }
        }
        return []
    }
}

/// One protocol's requirements, reduced to what an actor conforming to it can leak.
struct ProtocolIsolationShape {
    var inherited: Set<String> = []
    /// A requirement callable without `await` — one an actor can satisfy only with `nonisolated`
    /// or `@preconcurrency`.
    var hasSynchronous = false
    /// A requirement every caller reaches through `await`.
    var hasAwaited = false
    var isFileLocal = false

    /// Two declarations of one name merge conservatively: either one's synchronous requirement,
    /// or either one being file-local, disqualifies the name.
    mutating func merge(_ other: Self) {
        inherited.formUnion(other.inherited)
        hasSynchronous = hasSynchronous || other.hasSynchronous
        hasAwaited = hasAwaited || other.hasAwaited
        isFileLocal = isFileLocal || other.isFileLocal
    }

    /// The shape one protocol declaration spells.
    static func reading(_ node: ProtocolDeclSyntax) -> Self {
        var shape = Self()
        shape.inherited = ActorTypeCollector.names(in: node.inheritanceClause)
        // `protocol P where Self: Q` inherits `Q`'s requirements as surely as `P: Q` does.
        for requirement in node.genericWhereClause?.requirements ?? [] {
            guard case .conformanceRequirement(let conformance) = requirement.requirement,
                  conformance.leftType.as(IdentifierTypeSyntax.self)?.name.text == "Self"
            else { continue }
            shape.inherited.formUnion(ActorTypeCollector.names(of: conformance.rightType))
        }
        shape.isFileLocal = node.modifiers.contains {
            $0.name.tokenKind == .keyword(.private) || $0.name.tokenKind == .keyword(.fileprivate)
        }
        shape.classify(node.memberBlock.members)
        return shape
    }

    private mutating func classify(_ members: MemberBlockItemListSyntax) {
        for member in members {
            classify(member.decl)
        }
    }

    private mutating func classify(_ decl: DeclSyntax) {
        if let ifConfig = decl.as(IfConfigDeclSyntax.self) {
            // Every branch: a requirement in any configuration can be the one that leaks.
            for clause in ifConfig.clauses {
                if case .decls(let members) = clause.elements {
                    classify(members)
                }
            }
            return
        }
        for awaited in Self.instanceRequirements(of: decl) {
            if awaited { hasAwaited = true } else { hasSynchronous = true }
        }
    }

    /// For each instance requirement `decl` declares, whether a caller reaches it through `await`.
    /// `init`, `associatedtype`, `typealias` and `static` members declare none: none of them is
    /// isolated to an instance.
    private static func instanceRequirements(of decl: DeclSyntax) -> [Bool] {
        if let function = decl.as(FunctionDeclSyntax.self), !isTypeLevel(function.modifiers) {
            return [function.signature.effectSpecifiers?.asyncSpecifier != nil]
        }
        if let variable = decl.as(VariableDeclSyntax.self), !isTypeLevel(variable.modifiers) {
            return variable.bindings.map { isAwaited($0.accessorBlock) }
        }
        if let subscriptDecl = decl.as(SubscriptDeclSyntax.self),
           !isTypeLevel(subscriptDecl.modifiers) {
            return [isAwaited(subscriptDecl.accessorBlock)]
        }
        return []
    }

    /// `{ get async }` and `{ get async throws }` are awaited; `{ get }` and `{ get set }` are not.
    private static func isAwaited(_ block: AccessorBlockSyntax?) -> Bool {
        guard case .accessors(let accessors)? = block?.accessors, !accessors.isEmpty else {
            return false
        }
        return accessors.allSatisfy { $0.effectSpecifiers?.asyncSpecifier != nil }
    }

    /// A `static` or `class` requirement belongs to the type, and an actor's type-level members
    /// are not isolated to any instance.
    private static func isTypeLevel(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }
    }
}

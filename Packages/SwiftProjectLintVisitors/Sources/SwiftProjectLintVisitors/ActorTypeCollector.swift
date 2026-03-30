import SwiftSyntax

/// A fast SyntaxVisitor that collects the names of all top-level actor declarations.
///
/// Used as a project-wide pre-scan so that per-file visitors can exempt actor-typed
/// parameters and properties from rules like "Concrete Type Usage". Actors already
/// provide a strong isolation contract via Swift Concurrency — protocol-abstracting
/// an actor weakens that contract because the caller loses the actor's serial executor
/// guarantee and the compiler can no longer enforce await requirements at the call site.
public final class ActorTypeCollector: SyntaxVisitor, TypeCollectorProtocol {
    public var collectedTypes: Set<String> { actorTypes }

    /// The set of actor type names found across the project.
    private(set) var actorTypes: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        actorTypes.insert(node.name.text)
        return .visitChildren
    }
}

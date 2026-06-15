import SwiftSyntax

/// A fast SyntaxVisitor that collects the names of all protocol declarations.
///
/// Used as a project-wide pre-scan so that per-file visitors can tell a protocol
/// apart from a concrete service type. This prevents rules like "Concrete Type
/// Usage" from flagging a property/parameter typed as a protocol that is used as
/// a bare existential (`let provider: ResourceMetricsProvider`) — i.e. a protocol
/// whose name does not end in `Protocol`/`Type`/`Interface`, so the name-based
/// heuristic alone cannot recognise it.
public final class ProtocolTypeCollector: SyntaxVisitor, TypeCollectorProtocol {
    public var collectedTypes: Set<String> { protocolTypes }

    /// The set of protocol type names found across the project.
    private(set) var protocolTypes: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        protocolTypes.insert(node.name.text)
        return .visitChildren
    }
}

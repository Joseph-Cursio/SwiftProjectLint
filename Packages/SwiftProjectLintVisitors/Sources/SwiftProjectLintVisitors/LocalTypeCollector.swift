import SwiftSyntax

/// A fast SyntaxVisitor that collects the names of all top-level type declarations
/// (class, struct, enum, actor) across the project.
///
/// Used as a project-wide pre-scan so that per-file visitors can determine
/// whether an extended type is defined in the same module. The primary
/// consumer is `PreconcurrencyConformanceVisitor`, which flags `@preconcurrency`
/// on conformances where the extended type belongs to the project itself.
public final class LocalTypeCollector: SyntaxVisitor, TypeCollectorProtocol {
    public var collectedTypes: Set<String> { localTypes }

    private(set) var localTypes: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        localTypes.insert(node.name.text)
        return .visitChildren
    }

    override public func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        localTypes.insert(node.name.text)
        return .visitChildren
    }

    override public func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        localTypes.insert(node.name.text)
        return .visitChildren
    }

    override public func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        localTypes.insert(node.name.text)
        return .visitChildren
    }
}

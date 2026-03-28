import SwiftSyntax

/// A fast SyntaxVisitor that collects the names of all top-level enum declarations.
///
/// Used as a project-wide pre-scan so that per-file visitors can distinguish
/// enum types from class/struct service types. This prevents rules like
/// "Concrete Type Usage" from flagging enum-typed parameters or properties,
/// since enums are value types that cannot meaningfully be protocol-abstracted
/// in the same way as a service class.
final class EnumTypeCollector: SyntaxVisitor, TypeCollectorProtocol {
    var collectedTypes: Set<String> { enumTypes }

    /// The set of enum type names found across the project.
    private(set) var enumTypes: Set<String> = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        enumTypes.insert(node.name.text)
        return .visitChildren
    }
}

import SwiftSyntax

/// Collects the names of members declared under `@_spi(...)`.
///
/// `@_spi` is Swift's own mechanism for "public symbol, deliberately not public API": the
/// declaration is visible to a client that opts in with a matching `@_spi` import and invisible
/// to everyone else. A package that publishes one is entitled to use it.
///
/// Used as a project-wide pre-scan so `AccessingImplementationDetailsVisitor` can tell a leaked
/// internal from a declared one. That rule reads an underscore prefix as "implementation
/// detail", which is the right heuristic — but where the author has *also* written the
/// attribute, the underscore is the convention that accompanies the attribute rather than a
/// naming accident, and reporting it tells the author something they already said.
///
/// The attribute is honoured on the declaration itself or on an enclosing `extension`, which is
/// where it is usually written when a whole group of members is being published as SPI.
public final class SPIMemberCollector: SyntaxVisitor, TypeCollectorProtocol {
    public var collectedTypes: Set<String> { memberNames }

    private(set) var memberNames: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if Self.isSPI(node.attributes) || Self.isInsideSPIExtension(node) {
            memberNames.insert(node.name.text)
        }
        return .visitChildren
    }

    override public func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard Self.isSPI(node.attributes) || Self.isInsideSPIExtension(node) else {
            return .visitChildren
        }
        for binding in node.bindings {
            if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                memberNames.insert(identifier.identifier.text)
            }
        }
        return .visitChildren
    }

    private static func isSPI(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return attribute.attributeName.trimmedDescription == "_spi"
        }
    }

    /// Whether the declaration sits inside an `extension` carrying the attribute.
    private static func isInsideSPIExtension(_ node: some SyntaxProtocol) -> Bool {
        var current = node.parent
        while let candidate = current {
            if let extensionDecl = candidate.as(ExtensionDeclSyntax.self) {
                return isSPI(extensionDecl.attributes)
            }
            current = candidate.parent
        }
        return false
    }
}

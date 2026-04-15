import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects `@_disfavoredOverload` in production code.
///
/// `@_disfavoredOverload` is a compiler-internal attribute with no ABI stability
/// guarantee. Its leading-underscore prefix is Swift's explicit signal that this
/// attribute is not part of the public language surface and may change or disappear
/// between compiler versions.
///
/// **The legitimate use case** — biasing overload resolution toward a more specific
/// overload when both match equally — is real, but the attribute is the wrong tool.
/// If overload resolution produces the wrong result without it, the overload set
/// should be redesigned rather than patched with an unstable compiler knob.
///
/// **Suppression:** Not suppressed in test code; the attribute is equally fragile there.
final class DisfavoredOverloadVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        if hasDisfavoredOverload(node.attributes) {
            addIssue(node: Syntax(node))
        }
        return .visitChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        if hasDisfavoredOverload(node.attributes) {
            addIssue(node: Syntax(node))
        }
        return .visitChildren
    }

    private func hasDisfavoredOverload(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return attribute.attributeName.trimmedDescription == "_disfavoredOverload"
        }
    }
}

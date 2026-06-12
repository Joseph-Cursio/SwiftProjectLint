import SwiftSyntax

/// A fast SyntaxVisitor that collects the names of types participating in SwiftUI
/// observation — classes carrying the `@Observable` macro, or any class declaring
/// `ObservableObject` conformance.
///
/// Used as a project-wide pre-scan so that per-file visitors can exempt such types
/// from "prefer a protocol abstraction" suggestions (e.g. "Concrete Type Usage").
/// Hiding an observable model behind `any SomeProtocol` severs SwiftUI's observation
/// tracking: through the existential the view can no longer see the concrete
/// `@Observable`/`@Published` storage, so it stops re-rendering on change. The
/// concrete type is load-bearing here — like an actor's isolation contract — and
/// must not be protocol-abstracted.
///
/// `@Observable` and `ObservableObject` are both class-only, so only class
/// declarations are inspected.
public final class ObservableTypeCollector: SyntaxVisitor, TypeCollectorProtocol {
    public var collectedTypes: Set<String> { observableTypes }

    /// The set of observable type names found across the project.
    private(set) var observableTypes: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if hasObservableAttribute(node.attributes)
            || declaresObservableObject(node.inheritanceClause) {
            observableTypes.insert(node.name.text)
        }
        return .visitChildren
    }

    private func hasObservableAttribute(_ attributes: AttributeListSyntax) -> Bool {
        attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Observable"
        }
    }

    private func declaresObservableObject(_ inheritance: InheritanceClauseSyntax?) -> Bool {
        guard let inheritance else { return false }
        return inheritance.inheritedTypes.contains { inherited in
            inherited.type.as(IdentifierTypeSyntax.self)?.name.text == "ObservableObject"
        }
    }
}

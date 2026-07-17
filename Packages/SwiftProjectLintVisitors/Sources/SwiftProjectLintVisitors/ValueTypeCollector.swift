import SwiftSyntax

/// A project-wide pre-scan collecting the names of types declared as **value
/// types** — `struct` and `enum`. Actors and classes are reference types and are
/// deliberately excluded.
///
/// Per-file visitors cannot see a type's *kind* when they are looking at an
/// `extension` of it: `extension OrderedSet { … }` never repeats the `struct`
/// keyword, and the primary `struct OrderedSet` declaration usually lives in a
/// different file. So the kind is collected once, across the project, and
/// injected — exactly like `EquatableConformanceCollector`.
///
/// The Pure Function Property-Test Candidate rule uses it for one decision: a
/// method that reads a **bare `self`** (`var result = self`, `return self`,
/// `self == other`) is a function of `self` *only when `self` is a value* —
/// copying a struct reads its value, while copying a class aliases a shared
/// object. The set answers "is the enclosing type a value type?" for the
/// extension case that syntax alone cannot.
public final class ValueTypeCollector: SyntaxVisitor, TypeCollectorProtocol {
    public var collectedTypes: Set<String> { valueTypes }

    /// The names of every `struct` and `enum` declared across the project.
    private(set) var valueTypes: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        valueTypes.insert(node.name.text)
        return .visitChildren
    }

    override public func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        valueTypes.insert(node.name.text)
        return .visitChildren
    }
}

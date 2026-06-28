import SwiftSyntax

/// A project-wide pre-scan that collects the names of types known to be
/// `Equatable` — i.e. those declaring `Equatable`, `Hashable`, or `Comparable`
/// (each of the latter refines `Equatable`), whether inline
/// (`struct Foo: Equatable`) or via a separate `extension Foo: Equatable {}` in
/// any file.
///
/// Per-file visitors can't see conformances declared elsewhere, so this set is
/// built once and injected. The Pure Function Property-Test Candidate rule uses
/// it to gate seeds: a candidate is only useful to `swift-infer` if its result
/// can be asserted on, which requires the return type to be `Equatable`.
public final class EquatableConformanceCollector: SyntaxVisitor, TypeCollectorProtocol {

    public var collectedTypes: Set<String> { equatableTypes }

    private var equatableTypes: Set<String> = []

    /// Conformances that make a type `Equatable`. `Hashable` and `Comparable`
    /// both refine it, so declaring any one suffices.
    private static let equatableConformances: Set<String> = ["Equatable", "Hashable", "Comparable"]

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.inheritanceClause)
        return .visitChildren
    }

    override public func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.inheritanceClause)
        return .visitChildren
    }

    override public func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.inheritanceClause)
        return .visitChildren
    }

    override public func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        if let name = extendedTypeName(node.extendedType) {
            record(name, node.inheritanceClause)
        }
        return .visitChildren
    }

    private func record(_ name: String, _ inheritance: InheritanceClauseSyntax?) {
        guard let inheritance else { return }
        for inherited in inheritance.inheritedTypes {
            if let conformance = conformanceName(inherited.type),
               Self.equatableConformances.contains(conformance) {
                equatableTypes.insert(name)
                return
            }
        }
    }

    /// The simple name of a conformance, unwrapping attributes so
    /// `@retroactive Equatable` resolves to `Equatable`.
    private func conformanceName(_ type: TypeSyntax) -> String? {
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return conformanceName(attributed.baseType)
        }
        return type.as(IdentifierTypeSyntax.self)?.name.text
    }

    /// The simple name of an extended type: `extension Foo` → `Foo`,
    /// `extension Outer.Inner` → `Inner`.
    private func extendedTypeName(_ type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text
        }
        return nil
    }
}

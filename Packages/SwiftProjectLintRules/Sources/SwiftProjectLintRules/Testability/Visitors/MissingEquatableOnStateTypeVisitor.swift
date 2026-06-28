import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: flags a project value type (`struct`/`enum`) that is held
/// in SwiftUI state (`@State` / `@Binding` / `@Published`) but conforms to
/// neither `Equatable` nor `Hashable` anywhere in the project.
///
/// Why it matters for the pipeline: an `Equatable` state type is a direct
/// SwiftPropertyLaws target — equality is the precondition for property-test
/// assertions and shrinking. Surfacing the gap turns "untestable view state"
/// into "one conformance away from property-testable."
///
/// **Phase 1 (walk):** record every `struct`/`enum` declaration site, union the
/// conformances it declares — inline *and* via a separate `extension Foo:
/// Equatable {}` — and record the value types used in state property wrappers.
/// **Phase 2 (`finalizeAnalysis`):** emit one issue per value type that is used
/// in state yet declares neither `Equatable` nor `Hashable`.
///
/// Conservative by design (`info`): a type whose declaration isn't in the scanned
/// project (another module) is never flagged, since its conformances can't be
/// seen.
final class MissingEquatableOnStateTypeVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// Property wrappers that carry a *value* type worth making `Equatable`.
    /// Reference-type wrappers (`@StateObject`, `@ObservedObject`,
    /// `@EnvironmentObject`) are excluded — they wrap `ObservableObject`
    /// classes, where identity, not value equality, is the model.
    private static let valueStateWrappers: Set<String> = ["State", "Binding", "Published"]

    /// Conformances that make a value type usable as a property-test subject.
    /// `Hashable` refines `Equatable`, so either satisfies the rule.
    private static let equatableConformances: Set<String> = ["Equatable", "Hashable"]

    private struct Declaration {
        let file: String
        let line: Int
    }

    /// Value-type name → its declaration site (first one wins; partial-type
    /// re-declarations are rare and a single actionable location is enough).
    private var valueTypeDecls: [String: Declaration] = [:]
    /// Type name → every conformance it declares, unioned across the primary
    /// declaration and all `extension` blocks in any file.
    private var declaredConformances: [String: Set<String>] = [:]
    /// Base nominal names of value types observed in a state property wrapper.
    private var stateUsedTypes: Set<String> = []

    // MARK: - Phase 1: collect

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordValueType(node.name.text, node.inheritanceClause, Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordValueType(node.name.text, node.inheritanceClause, Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // A conformance can be added away from the declaration:
        // `extension Foo: Equatable {}`. Union it in; we don't yet know whether
        // `Foo` is a value type, so just accumulate — the finalize step only
        // consults conformances for names that turned out to be value types.
        if let name = extendedTypeName(node.extendedType) {
            mergeConformances(of: name, from: node.inheritanceClause)
        }
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let wrapper = stateWrapperName(node.attributes),
              Self.valueStateWrappers.contains(wrapper) else {
            return .visitChildren
        }
        for binding in node.bindings {
            if let name = stateValueTypeName(binding) {
                stateUsedTypes.insert(name)
            }
        }
        return .visitChildren
    }

    private func recordValueType(
        _ name: String,
        _ inheritance: InheritanceClauseSyntax?,
        _ node: Syntax
    ) {
        if valueTypeDecls[name] == nil {
            valueTypeDecls[name] = Declaration(file: currentFilePath, line: getLineNumber(for: node))
        }
        mergeConformances(of: name, from: inheritance)
    }

    private func mergeConformances(of name: String, from inheritance: InheritanceClauseSyntax?) {
        guard let inheritance else { return }
        for inherited in inheritance.inheritedTypes {
            if let conformance = conformanceName(inherited.type) {
                declaredConformances[name, default: []].insert(conformance)
            }
        }
    }

    // MARK: - Phase 2: emit

    func finalizeAnalysis() {
        for name in stateUsedTypes.sorted() {
            guard let declaration = valueTypeDecls[name] else { continue } // external type → can't judge
            let conformances = declaredConformances[name] ?? []
            guard conformances.isDisjoint(with: Self.equatableConformances) else { continue }

            addIssue(
                severity: .info,
                message: "'\(name)' is held in SwiftUI state but conforms to neither Equatable "
                    + "nor Hashable, so it can't be a property-test subject",
                filePath: declaration.file,
                lineNumber: declaration.line,
                suggestion: "Add `Equatable` (or `Hashable`) to '\(name)' so its state can be "
                    + "asserted on and shrunk by property-based tests.",
                ruleName: .missingEquatableOnStateType
            )
        }
    }

    // MARK: - Syntax helpers

    /// The simple name of a property wrapper attribute, e.g. `@State` → `"State"`.
    private func stateWrapperName(_ attributes: AttributeListSyntax) -> String? {
        for attribute in attributes {
            if let attributeSyntax = attribute.as(AttributeSyntax.self),
               let name = attributeSyntax.attributeName.as(IdentifierTypeSyntax.self)?.name.text {
                return name
            }
        }
        return nil
    }

    /// The base nominal type a state binding carries, from its annotation
    /// (`: Foo`, `: Foo?`, `: [Foo]`) or, lacking one, a simple initializer
    /// (`= Foo()`). Returns `nil` for closures, tuples, and anything without a
    /// resolvable nominal base.
    private func stateValueTypeName(_ binding: PatternBindingSyntax) -> String? {
        if let annotated = binding.typeAnnotation?.type {
            return baseTypeName(annotated)
        }
        if let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
           let callee = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return callee.baseName.text
        }
        return nil
    }

    /// Unwraps optionals and arrays to the underlying nominal name: `Foo?` →
    /// `Foo`, `[Foo]` → `Foo`, `Foo<Bar>` → `Foo`.
    private func baseTypeName(_ type: TypeSyntax) -> String? {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return baseTypeName(optional.wrappedType)
        }
        if let implicit = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return baseTypeName(implicit.wrappedType)
        }
        if let array = type.as(ArrayTypeSyntax.self) {
            return baseTypeName(array.element)
        }
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        return nil
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

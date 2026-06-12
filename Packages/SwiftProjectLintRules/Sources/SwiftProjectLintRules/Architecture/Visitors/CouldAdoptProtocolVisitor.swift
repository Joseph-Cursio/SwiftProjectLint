import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: detects a concrete type that structurally satisfies a project-declared,
/// property-only protocol's requirements but does not declare conformance — it *could adopt*
/// the existing protocol. The inverse of `DuplicateStructShape`: there the shared shape has no
/// protocol; here a matching protocol already exists. See `Docs/rules/could-adopt-protocol.md`.
///
/// **Phase 1 (walk):** collect property-only protocols with their `(name, type, optional)`
/// requirement signatures, and concrete types with their stored-property signatures and
/// declared conformances.
/// **Phase 2 (finalize):** for each type/protocol pair, if the type's signatures are a
/// superset of the protocol's requirements and the type does not already conform, report it.
final class CouldAdoptProtocolVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// Protocols with fewer requirements than this are too generic to suggest adoption.
    private static let minimumRequirements = 3
    private static let skippedConformances: Set<String> = ["View", "ViewModifier"]

    private struct PropertySignature: Hashable {
        let name: String
        let type: String
        let isOptional: Bool
    }

    private struct ProtocolShape {
        let name: String
        let requirements: Set<PropertySignature>
    }

    private struct TypeShape {
        let name: String
        let file: String
        let line: Int
        let signatures: Set<PropertySignature>
        let conformances: Set<String>
    }

    private var protocolShapes: [ProtocolShape] = []
    private var typeShapes: [TypeShape] = []

    // MARK: - Phase 1: collect

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        var requirements: Set<PropertySignature> = []
        var propertyOnly = true
        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
                // Any non-property requirement (func, associatedtype, init, subscript) makes
                // structural matching unreliable — exclude the protocol entirely.
                propertyOnly = false
                break
            }
            for binding in varDecl.bindings {
                guard let id = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let annotation = binding.typeAnnotation?.type else { continue }
                let (normalized, isOptional) = normalize(annotation)
                requirements.insert(PropertySignature(name: id, type: normalized, isOptional: isOptional))
            }
        }
        if propertyOnly, requirements.count >= Self.minimumRequirements {
            protocolShapes.append(ProtocolShape(name: node.name.text, requirements: requirements))
        }
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node.name.text, node.memberBlock, node.inheritanceClause, Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordType(node.name.text, node.memberBlock, node.inheritanceClause, Syntax(node))
        return .visitChildren
    }

    private func recordType(
        _ name: String,
        _ members: MemberBlockSyntax,
        _ inheritance: InheritanceClauseSyntax?,
        _ node: Syntax
    ) {
        var conformances: Set<String> = []
        if let inheritance {
            for inherited in inheritance.inheritedTypes {
                if let conformanceName = conformanceName(inherited.type) {
                    conformances.insert(conformanceName)
                }
            }
        }
        guard Self.skippedConformances.isDisjoint(with: conformances) else { return }

        let signatures = members.members.reduce(into: Set<PropertySignature>()) { acc, member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  isStoredInstanceProperty(varDecl) else { return }
            for binding in varDecl.bindings {
                guard let id = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let annotation = binding.typeAnnotation?.type else { continue }
                let (normalized, isOptional) = normalize(annotation)
                acc.insert(PropertySignature(name: id, type: normalized, isOptional: isOptional))
            }
        }
        guard signatures.isEmpty == false else { return }

        typeShapes.append(TypeShape(
            name: name,
            file: currentFilePath,
            line: getLineNumber(for: node),
            signatures: signatures,
            conformances: conformances
        ))
    }

    // MARK: - Phase 2: report

    func finalizeAnalysis() {
        for type in typeShapes {
            for proto in protocolShapes {
                guard type.conformances.contains(proto.name) == false,
                      proto.requirements.isSubset(of: type.signatures) else { continue }
                let props = proto.requirements.map(\.name).sorted().joined(separator: ", ")
                addIssue(
                    severity: .info,
                    message: "'\(type.name)' has all stored properties required by protocol "
                        + "'\(proto.name)' (\(props)) but does not conform to it.",
                    filePath: type.file,
                    lineNumber: type.line,
                    suggestion: "Declare conformance — '\(type.name): \(proto.name)' — to reuse "
                        + "the existing abstraction instead of an incidental structural match.",
                    ruleName: .couldAdoptProtocol
                )
            }
        }
    }

    // MARK: - Shared helpers

    private func conformanceName(_ type: TypeSyntax) -> String? {
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return conformanceName(attributed.baseType)
        }
        return type.as(IdentifierTypeSyntax.self)?.name.text
    }

    private func isStoredInstanceProperty(_ varDecl: VariableDeclSyntax) -> Bool {
        for modifier in varDecl.modifiers
        where ["static", "class", "lazy"].contains(modifier.name.text) {
            return false
        }
        for binding in varDecl.bindings where isComputed(binding) {
            return false
        }
        return true
    }

    private func isComputed(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessorBlock = binding.accessorBlock else { return false }
        switch accessorBlock.accessors {
        case .getter:
            return true

        case .accessors(let list):
            return list.contains { ["get", "set"].contains($0.accessorSpecifier.text) }
        }
    }

    private func normalize(_ type: TypeSyntax) -> (String, Bool) {
        if let optional = type.as(OptionalTypeSyntax.self) {
            return (optional.wrappedType.trimmedDescription, true)
        }
        if let implicit = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return (implicit.wrappedType.trimmedDescription, true)
        }
        if let ident = type.as(IdentifierTypeSyntax.self),
           ident.name.text == "Optional",
           let inner = ident.genericArgumentClause?.arguments.first?.argument.as(TypeSyntax.self) {
            return (inner.trimmedDescription, true)
        }
        return (type.trimmedDescription, false)
    }
}

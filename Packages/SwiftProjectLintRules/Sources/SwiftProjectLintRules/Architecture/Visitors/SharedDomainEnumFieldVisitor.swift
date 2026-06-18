import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: flags three or more sibling types that each carry a stored
/// property of the *same name and the same project-declared enum type*, yet share no
/// common protocol declaring it. A shared domain enum (`IssueSeverity`, `LoadState`)
/// repeated as a field across unrelated types is an implicit axis that usually wants a
/// marker protocol, so behavior keyed on it (sorting, filtering, grouping) can be
/// written once. See `Docs/rules/shared-domain-enum-field.md`.
///
/// The "project-declared enum" requirement is the false-positive guard that
/// distinguishes this from a naive low-threshold `DuplicateStructShape`: ubiquitous
/// fields like `id: UUID`, `name: String`, or `isEnabled: Bool` are not domain axes and
/// are ignored. Only an enum *declared in the analyzed sources* counts.
///
/// **Phase 1 (walk):** record project enum names, protocol property requirements, and
/// every type's stored-property `(name, type)` signatures with its conformances.
/// **Phase 2 (`finalizeAnalysis`):** keep only fields whose type is a project enum,
/// cluster types by `(propertyName, enumType)`, drop types already covered by a shared
/// protocol, and emit one issue per remaining type when a cluster still has `>= minimumCluster`.
final class SharedDomainEnumFieldVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// Two types sharing a field is coincidence-prone; require three before nudging
    /// toward an abstraction. (One shared field is a far weaker signal than
    /// `DuplicateStructShape`'s four, so the cluster threshold is higher to compensate.)
    private static let minimumCluster = 3

    /// SwiftUI types carry state-shaped fields by design; clustering them is noise.
    private static let skippedConformances: Set<String> = ["View", "ViewModifier"]

    private struct FieldSignature: Hashable {
        let propertyName: String
        let typeName: String
    }

    private struct TypeShape {
        let name: String
        let file: String
        let line: Int
        let fields: Set<FieldSignature>
        let conformances: Set<String>
    }

    private var projectEnumNames: Set<String> = []
    private var shapes: [TypeShape] = []
    /// Protocol name → its property-requirement names (sufficient for the coverage check).
    private var protocolRequirementNames: [String: Set<String>] = [:]

    // MARK: - Phase 1: collect

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        projectEnumNames.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let names = node.memberBlock.members.compactMap { member -> String? in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return nil }
            return varDecl.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text
        }
        protocolRequirementNames[node.name.text] = Set(names)
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordShape(node.name.text, node.memberBlock, node.inheritanceClause, Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordShape(node.name.text, node.memberBlock, node.inheritanceClause, Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordShape(node.name.text, node.memberBlock, node.inheritanceClause, Syntax(node))
        return .visitChildren
    }

    private func recordShape(
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

        // Collect every nominally-typed stored property; the enum filter is applied in
        // Phase 2, once all enum declarations across files have been seen.
        let fields = members.members.reduce(into: Set<FieldSignature>()) { acc, member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  isStoredInstanceProperty(varDecl) else { return }
            for binding in varDecl.bindings {
                guard let id = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let typeName = nominalTypeName(binding.typeAnnotation?.type) else { continue }
                acc.insert(FieldSignature(propertyName: id, typeName: typeName))
            }
        }
        guard fields.isEmpty == false else { return }

        shapes.append(TypeShape(
            name: name,
            file: currentFilePath,
            line: getLineNumber(for: node),
            fields: fields,
            conformances: conformances
        ))
    }

    // MARK: - Phase 2: cluster + emit

    func finalizeAnalysis() {
        // Restrict each type's fields to those whose type is a project-declared enum.
        let enumShapes: [(shape: TypeShape, enumFields: Set<FieldSignature>)] = shapes.compactMap { shape in
            let enumFields = shape.fields.filter { projectEnumNames.contains($0.typeName) }
            return enumFields.isEmpty ? nil : (shape, enumFields)
        }
        guard enumShapes.count >= Self.minimumCluster else { return }

        // Cluster by the (propertyName, enumType) signature.
        var clusters: [FieldSignature: [TypeShape]] = [:]
        for entry in enumShapes {
            for field in entry.enumFields {
                clusters[field, default: []].append(entry.shape)
            }
        }

        for (signature, members) in clusters where members.count >= Self.minimumCluster {
            // A type already conforming to a protocol that declares this property is
            // abstracted — drop it before deciding whether a cluster remains.
            let reportable = members.filter {
                conformsToCovering($0, propertyName: signature.propertyName) == false
            }
            guard reportable.count >= Self.minimumCluster else { continue }

            let allNames = reportable.map(\.name).sorted()
            let fieldText = "\(signature.propertyName): \(signature.typeName)"
            for shape in reportable {
                let peers = allNames.filter { $0 != shape.name }.joined(separator: ", ")
                addIssue(
                    severity: .info,
                    message: "'\(shape.name)' carries domain-enum field '\(fieldText)' shared "
                        + "with \(peers) but no common protocol.",
                    filePath: shape.file,
                    lineNumber: shape.line,
                    suggestion: "Extract a protocol requiring '\(fieldText)' and conform "
                        + "\(allNames.joined(separator: ", ")) to it, so behavior keyed on "
                        + "\(signature.typeName) (sorting, filtering, grouping) is written once.",
                    ruleName: .sharedDomainEnumField
                )
            }
        }
    }

    /// True when the type already conforms to a protocol whose requirements include the
    /// shared property — the abstraction is present, so there is nothing to extract.
    private func conformsToCovering(_ shape: TypeShape, propertyName: String) -> Bool {
        shape.conformances.contains { protocolName in
            (protocolRequirementNames[protocolName] ?? []).contains(propertyName)
        }
    }

    // MARK: - Shared helpers

    /// Stored, instance-level, non-computed. `static`/`class`/`lazy` and computed
    /// properties are not domain state.
    private func isStoredInstanceProperty(_ varDecl: VariableDeclSyntax) -> Bool {
        for modifier in varDecl.modifiers
        where ["static", "class", "lazy"].contains(modifier.name.text) {
            return false
        }
        for binding in varDecl.bindings where binding.accessorBlock != nil {
            return false
        }
        return true
    }

    /// The simple name of a conformance, unwrapping attributed conformances
    /// (`@MainActor P`, `@retroactive P`) to `P`.
    private func conformanceName(_ type: TypeSyntax) -> String? {
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return conformanceName(attributed.baseType)
        }
        return type.as(IdentifierTypeSyntax.self)?.name.text
    }

    /// The plain nominal type name of a property annotation, or `nil` for optionals,
    /// arrays, generics, tuples, and functions. Restricting to a bare identifier keeps
    /// the rule on the clean `severity: IssueSeverity` case: an optional or boxed enum
    /// field is a weaker domain-axis signal and would complicate the suggested protocol
    /// requirement, so v1 leaves those out.
    private func nominalTypeName(_ type: TypeSyntax?) -> String? {
        guard let ident = type?.as(IdentifierTypeSyntax.self),
              ident.genericArgumentClause == nil else { return nil }
        return ident.name.text
    }
}

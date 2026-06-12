import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: flags clusters of unrelated types that share an identical
/// stored-property core but no common protocol/superclass — an implicit abstraction
/// that should be made explicit. See `Docs/rules/duplicate-struct-shape.md`.
///
/// **Phase 1 (walk):** fingerprint every struct/class by its stored properties and
/// collect protocol property-requirement names.
/// **Phase 2 (`finalizeAnalysis`):** cluster types sharing `>= minimumShared` identical
/// signatures, drop clusters already covered by a shared protocol, then emit one issue
/// per participating type.
final class DuplicateStructShapeVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    // Tunable thresholds. Per-rule YAML config is a follow-up; these match the
    // hardcoded-threshold convention used by the other Architecture visitors.
    private static let minimumShared = 4
    private static let minimumClusterSize = 2

    /// SwiftUI types whose stored properties (`@State`, `@Binding`, closures) are shared by
    /// design when one view bridges to another — clustering them produces noise, not missing
    /// abstractions. Types declaring conformance to any of these are skipped entirely.
    ///
    /// Detection is by inheritance-clause name only: it cannot distinguish SwiftUI's `View`
    /// from a same-named local protocol, and does not see conformance added via a separate
    /// `extension Foo: View {}`. In practice SwiftUI views declare `: View` inline, so this
    /// covers the real cases.
    private static let skippedConformances: Set<String> = ["View", "ViewModifier"]

    /// One stored property's identity. `Hashable` so a `Set` of these forms the fingerprint.
    private struct PropertySignature: Hashable {
        let name: String
        let type: String       // normalized: `Optional<T>`/`T?` unwrapped, whitespace-stripped
        let isOptional: Bool
    }

    private struct TypeShape {
        let name: String
        let file: String
        let line: Int          // captured during the walk — converter is correct per-file
        let signatures: Set<PropertySignature>
        let conformances: Set<String>
    }

    private var shapes: [TypeShape] = []
    /// Protocol name → its property requirement names (sufficient for the coverage check).
    private var protocolRequirementNames: [String: Set<String>] = [:]

    // MARK: - Phase 1: collect

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordShape(node.name.text, node.memberBlock, node.inheritanceClause, Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordShape(node.name.text, node.memberBlock, node.inheritanceClause, Syntax(node))
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

    private func recordShape(
        _ name: String,
        _ members: MemberBlockSyntax,
        _ inheritance: InheritanceClauseSyntax?,
        _ node: Syntax
    ) {
        var conformances: Set<String> = []
        if let inheritance {
            for inherited in inheritance.inheritedTypes {
                if let name = conformanceName(inherited.type) {
                    conformances.insert(name)
                }
            }
        }
        // SwiftUI views/modifiers share state-carrying properties by design — skip them so
        // bridge-pair views don't read as missing data-model abstractions.
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

        shapes.append(TypeShape(
            name: name,
            file: currentFilePath,
            line: getLineNumber(for: node),
            signatures: signatures,
            conformances: conformances
        ))
    }

    /// Stored, instance-level, non-computed. `willSet`/`didSet` observers still count as stored.
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

    /// The simple name of a conformance, unwrapping attributes so isolated/attributed
    /// conformances (`@MainActor P`, `@retroactive P`, `@preconcurrency P`) resolve to `P`.
    private func conformanceName(_ type: TypeSyntax) -> String? {
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return conformanceName(attributed.baseType)
        }
        return type.as(IdentifierTypeSyntax.self)?.name.text
    }

    private func isComputed(_ binding: PatternBindingSyntax) -> Bool {
        guard let accessorBlock = binding.accessorBlock else { return false }
        switch accessorBlock.accessors {
        case .getter:
            return true        // single-expression computed getter

        case .accessors(let list):
            return list.contains { ["get", "set"].contains($0.accessorSpecifier.text) }
        }
    }

    /// Canonicalize `Optional<T>`/`T?`; report optionality separately so `T` and `T?` differ.
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

    // MARK: - Phase 2: cluster + emit

    func finalizeAnalysis() {
        guard shapes.count >= Self.minimumClusterSize else { return }

        // Union-find: link two types when they share >= minimumShared identical signatures.
        var parent = Array(shapes.indices)
        func find(_ index: Int) -> Int {
            var root = index
            while parent[root] != root { root = parent[root] }
            var current = index
            while parent[current] != root { let next = parent[current]; parent[current] = root; current = next }
            return root
        }
        func union(_ lhs: Int, _ rhs: Int) { parent[find(lhs)] = find(rhs) }

        for lhsIndex in shapes.indices {
            for rhsIndex in (lhsIndex + 1)..<shapes.count
            where shapes[lhsIndex].signatures.intersection(shapes[rhsIndex].signatures).count >= Self.minimumShared {
                union(lhsIndex, rhsIndex)
            }
        }

        var clusters: [Int: [Int]] = [:]
        for index in shapes.indices { clusters[find(index), default: []].append(index) }

        for indices in clusters.values where indices.count >= Self.minimumClusterSize {
            let members = indices.map { shapes[$0] }
            let core = members.dropFirst().reduce(members[0].signatures) {
                $0.intersection($1.signatures)
            }
            guard core.count >= Self.minimumShared else { continue }

            // Coverage is a per-type question: a type that already conforms to a protocol
            // covering the core is abstracted and should not be reported, even when it sits
            // in a cluster alongside types that are not. Drop those before reporting.
            let coreNames = Set(core.map(\.name))
            let reportable = members.filter { conformsToCovering($0, coreNames: coreNames) == false }
            guard reportable.count >= Self.minimumClusterSize else { continue }

            let allNames = reportable.map(\.name).sorted()
            let propertyList = core.map(\.name).sorted().joined(separator: ", ")
            for shape in reportable {
                let peers = allNames.filter { $0 != shape.name }.joined(separator: ", ")
                addIssue(
                    severity: .info,
                    message: "'\(shape.name)' shares \(core.count) stored properties "
                        + "(\(propertyList)) with \(peers) but no common protocol.",
                    filePath: shape.file,
                    lineNumber: shape.line,
                    suggestion: "Extract a protocol declaring \(propertyList) and conform "
                        + "\(allNames.joined(separator: ", ")) to it.",
                    ruleName: .duplicateStructShape
                )
            }
        }
    }

    /// True when this type already conforms to a protocol whose requirements cover the core —
    /// the abstraction is present for this type, so there is nothing to extract.
    private func conformsToCovering(_ shape: TypeShape, coreNames: Set<String>) -> Bool {
        shape.conformances.contains { protocolName in
            (protocolRequirementNames[protocolName] ?? []).isSuperset(of: coreNames)
        }
    }
}

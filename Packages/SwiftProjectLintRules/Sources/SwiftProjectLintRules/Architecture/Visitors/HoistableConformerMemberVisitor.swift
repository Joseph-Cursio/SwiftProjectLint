import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: flags a method or computed property that three or more types
/// conforming to a common protocol `P` each implement *identically*, where the shared
/// body references only `P`'s requirements. Such a member can move into `extension P`
/// as a single default implementation. The behavioral inverse of `CouldAdoptProtocol`:
/// there a type structurally matches a protocol it has not adopted; here conformers of
/// an adopted protocol duplicate behavior the protocol could provide once.
/// See `Docs/rules/hoistable-conformer-member.md`.
///
/// **Phase 1 (walk):** record protocol requirement names, members provided by protocol
/// extensions, and — per concrete type, aggregated across its primary declaration and
/// extensions — its conformances, all member names, and its hoistable-member records
/// (signature, normalized body, referenced identifiers).
/// **Phase 2 (`finalizeAnalysis`):** group members by `(signature, body)`; for a group
/// spanning `>= minimumTypes` types that share a protocol `P` whose requirements cover
/// every instance member the body touches — and that does not already declare or provide
/// the member — emit one issue per participating type.
final class HoistableConformerMemberVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// Two identical implementations are coincidence-prone; require three before
    /// suggesting the abstraction move.
    private static let minimumTypes = 3

    /// SwiftUI types share boilerplate by design; clustering them is noise.
    private static let skippedConformances: Set<String> = ["View", "ViewModifier"]

    /// One hoistable member implementation on a concrete type.
    private struct MemberRecord {
        let owner: String
        let memberName: String
        let signatureKey: String
        let body: String
        let referencedIdentifiers: Set<String>
        let file: String
        let line: Int
    }

    /// An extension whose owner can't be classified as protocol-vs-type until every
    /// protocol declaration has been seen; resolved in `finalizeAnalysis`.
    private struct PendingExtension {
        let extendedName: String
        let conformances: Set<String>
        let memberNames: Set<String>
        let providedMembers: [MemberRecord]
    }

    private var declaredProtocolNames: Set<String> = []
    private var protocolRequirementNames: [String: Set<String>] = [:]
    private var protocolExtensionMemberNames: [String: Set<String>] = [:]

    private var typeConformances: [String: Set<String>] = [:]
    private var typeAllMemberNames: [String: Set<String>] = [:]
    private var records: [MemberRecord] = []
    private var pendingExtensions: [PendingExtension] = []

    // MARK: - Phase 1: collect

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        declaredProtocolNames.insert(name)
        protocolRequirementNames[name, default: []].formUnion(memberNames(of: node.memberBlock))
        return .visitChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        registerType(node.name.text, node.inheritanceClause, node.memberBlock)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        registerType(node.name.text, node.inheritanceClause, node.memberBlock)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        registerType(node.name.text, node.inheritanceClause, node.memberBlock)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        registerType(node.name.text, node.inheritanceClause, node.memberBlock)
        return .visitChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let extendedName = extendedTypeName(node.extendedType) else { return .visitChildren }
        pendingExtensions.append(PendingExtension(
            extendedName: extendedName,
            conformances: conformanceNames(node.inheritanceClause),
            memberNames: memberNames(of: node.memberBlock),
            providedMembers: hoistableMembers(in: node.memberBlock, owner: extendedName)
        ))
        return .visitChildren
    }

    private func registerType(
        _ name: String,
        _ inheritance: InheritanceClauseSyntax?,
        _ members: MemberBlockSyntax
    ) {
        typeConformances[name, default: []].formUnion(conformanceNames(inheritance))
        typeAllMemberNames[name, default: []].formUnion(memberNames(of: members))
        records.append(contentsOf: hoistableMembers(in: members, owner: name))
    }

    // MARK: - Phase 2: classify, group, emit

    func finalizeAnalysis() {
        // Classify deferred extensions now that every protocol name is known: extensions
        // of a protocol contribute default implementations; extensions of a type add to
        // that type's conformances and members.
        for ext in pendingExtensions {
            if declaredProtocolNames.contains(ext.extendedName) {
                protocolExtensionMemberNames[ext.extendedName, default: []]
                    .formUnion(ext.memberNames)
            } else {
                typeConformances[ext.extendedName, default: []].formUnion(ext.conformances)
                typeAllMemberNames[ext.extendedName, default: []].formUnion(ext.memberNames)
                records.append(contentsOf: ext.providedMembers)
            }
        }

        // Drop members of SwiftUI types entirely.
        let reportable = records.filter { record in
            Self.skippedConformances.isDisjoint(with: typeConformances[record.owner] ?? [])
        }

        // Group identical implementations by (signature, body).
        var groups: [String: [MemberRecord]] = [:]
        for record in reportable {
            groups[record.signatureKey + "\u{1}" + record.body, default: []].append(record)
        }

        for group in groups.values {
            let owners = Set(group.map(\.owner))
            guard owners.count >= Self.minimumTypes else { continue }
            guard let sample = group.first else { continue }

            guard let proto = hoistTarget(for: group, owners: owners) else { continue }

            // One issue per owning type, at its implementation's location.
            var seen: Set<String> = []
            let peers = owners.sorted()
            for record in group where seen.insert(record.owner).inserted {
                let others = peers.filter { $0 != record.owner }.joined(separator: ", ")
                addIssue(
                    severity: .info,
                    message: "'\(record.owner)' implements '\(sample.memberName)' identically to "
                        + "\(others) using only requirements of '\(proto)'.",
                    filePath: record.file,
                    lineNumber: record.line,
                    suggestion: "Hoist '\(sample.memberName)' into 'extension \(proto)' as a "
                        + "default implementation and remove the per-type copies.",
                    ruleName: .hoistableConformerMember
                )
            }
        }
    }

    /// The most specific protocol the group can hoist into, or `nil` if none qualifies.
    /// A protocol qualifies when every owner conforms to it, the body touches at least one
    /// of its requirements and *only* its requirements, the member is not itself a
    /// requirement (that would change the contract, not factor out incidental behavior),
    /// and no existing protocol extension already provides it.
    private func hoistTarget(for group: [MemberRecord], owners: Set<String>) -> String? {
        guard let sample = group.first else { return nil }

        let shared = owners
            .map { typeConformances[$0] ?? [] }
            .reduce(into: Set<String>()) { $0.formUnion($1) }
        let common = owners.reduce(shared) { $0.intersection(typeConformances[$1] ?? []) }

        let ownerMembers = owners.reduce(into: Set<String>()) {
            $0.formUnion(typeAllMemberNames[$1] ?? [])
        }
        let instanceRefs = sample.referencedIdentifiers.intersection(ownerMembers)

        let candidates = common.filter { proto in
            let requirements = protocolRequirementNames[proto] ?? []
            return requirements.contains(sample.memberName) == false
                && (protocolExtensionMemberNames[proto] ?? []).contains(sample.memberName) == false
                && instanceRefs.isEmpty == false
                && instanceRefs.isSubset(of: requirements)
        }

        // Prefer the tightest fit (fewest requirements); break ties by name for stability.
        return candidates.min { lhs, rhs in
            let lhsCount = (protocolRequirementNames[lhs] ?? []).count
            let rhsCount = (protocolRequirementNames[rhs] ?? []).count
            return lhsCount == rhsCount ? lhs < rhs : lhsCount < rhsCount
        }
    }

    // MARK: - Helpers

    /// The simple names of every method and property declared in a member block.
    private func memberNames(of members: MemberBlockSyntax) -> Set<String> {
        var names: Set<String> = []
        for member in members.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                names.insert(funcDecl.name.text)
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    if let id = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                        names.insert(id)
                    }
                }
            }
        }
        return names
    }

    /// Hoistable member records: instance methods with a body, and computed instance
    /// properties. Stored properties cannot move to a protocol extension and are skipped.
    private func hoistableMembers(in members: MemberBlockSyntax, owner: String) -> [MemberRecord] {
        var result: [MemberRecord] = []
        for member in members.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                guard isInstance(funcDecl.modifiers), let body = funcDecl.body else { continue }
                result.append(MemberRecord(
                    owner: owner,
                    memberName: funcDecl.name.text,
                    signatureKey: "func \(funcDecl.name.text)\(funcDecl.signature.trimmedDescription)",
                    body: normalize(body.trimmedDescription),
                    referencedIdentifiers: identifiers(in: Syntax(body)),
                    file: currentFilePath,
                    line: getLineNumber(for: Syntax(funcDecl))
                ))
            } else if let varDecl = member.decl.as(VariableDeclSyntax.self),
                      isInstance(varDecl.modifiers),
                      varDecl.bindings.count == 1,
                      let binding = varDecl.bindings.first,
                      let id = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      let accessor = binding.accessorBlock {
                let typeText = binding.typeAnnotation?.type.trimmedDescription ?? ""
                result.append(MemberRecord(
                    owner: owner,
                    memberName: id,
                    signatureKey: "var \(id):\(typeText)",
                    body: normalize(accessor.trimmedDescription),
                    referencedIdentifiers: identifiers(in: Syntax(accessor)),
                    file: currentFilePath,
                    line: getLineNumber(for: Syntax(varDecl))
                ))
            }
        }
        return result
    }

    /// Instance-level only — `static`/`class`/`lazy` members are not protocol-extension
    /// candidates in the same way and would change semantics if hoisted.
    private func isInstance(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { ["static", "class", "lazy"].contains($0.name.text) } == false
    }

    /// Body text canonicalized so trivial differences don't split a group: whitespace
    /// removed and the optional `self.` receiver dropped (`self.name` ≡ `name`).
    private func normalize(_ text: String) -> String {
        String(text.filter { !$0.isWhitespace }).replacingOccurrences(of: "self.", with: "")
    }

    /// Every identifier token in a body — used to find which instance members the body
    /// touches. Over-collection is safe: an extra name that isn't an owner member is
    /// filtered out by the `instanceRefs` intersection, and an extra name that *is* a
    /// member only ever makes the hoist guard stricter, never looser.
    private func identifiers(in node: Syntax) -> Set<String> {
        node.tokens(viewMode: .sourceAccurate).reduce(into: Set<String>()) { acc, token in
            if case .identifier = token.tokenKind { acc.insert(token.text) }
        }
    }

    private func conformanceNames(_ inheritance: InheritanceClauseSyntax?) -> Set<String> {
        guard let inheritance else { return [] }
        return inheritance.inheritedTypes.reduce(into: Set<String>()) { acc, inherited in
            if let name = conformanceName(inherited.type) { acc.insert(name) }
        }
    }

    /// The simple name of a conformance, unwrapping attributes (`@MainActor P` → `P`).
    private func conformanceName(_ type: TypeSyntax) -> String? {
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return conformanceName(attributed.baseType)
        }
        return type.as(IdentifierTypeSyntax.self)?.name.text
    }

    /// The base name of an extended type: `Foo` for `extension Foo` and `Inner` for
    /// `extension Outer.Inner`.
    private func extendedTypeName(_ type: TypeSyntax) -> String? {
        if let ident = type.as(IdentifierTypeSyntax.self) { return ident.name.text }
        if let member = type.as(MemberTypeSyntax.self) { return member.name.text }
        return nil
    }
}

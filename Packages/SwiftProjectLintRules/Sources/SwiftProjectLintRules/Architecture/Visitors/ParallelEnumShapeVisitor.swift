import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: flags two or more associated-value-free enums that declare an
/// identical case-name set but share no domain protocol — an implicit "same concept,
/// modeled twice" that should be one enum or a shared protocol. The structural twin of
/// `ScatteredEnumMapping` and the enum analogue of `DuplicateStructShape`.
/// See `Docs/rules/parallel-enum-shape.md`.
///
/// **Phase 1 (walk):** catalog every enum's case-name set, whether it has associated
/// values, and its (non-ubiquitous) conformances.
/// **Phase 2 (`finalizeAnalysis`):** cluster enums by identical case-name set, drop
/// clusters already unified by a shared domain protocol, then emit one issue per member.
final class ParallelEnumShapeVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    private static let minLabels = 3        // 2-case enums coincide too often (on/off, yes/no)
    private static let minClusterSize = 2   // need at least two enums to be "parallel"

    /// Raw-value types and ubiquitous standard protocols are not *domain* abstractions —
    /// two enums both conforming to `String`/`Equatable` are not "already unified". Only
    /// conformances outside this set count as a shared protocol that suppresses the rule.
    private static let ubiquitousConformances: Set<String> = [
        "String", "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Double", "Float", "Bool", "Character", "Substring",
        "CaseIterable", "Equatable", "Hashable", "Comparable", "Identifiable",
        "Codable", "Encodable", "Decodable", "Sendable", "RawRepresentable",
        "CustomStringConvertible", "CustomDebugStringConvertible", "Error", "LocalizedError"
    ]

    private struct EnumInfo {
        let name: String
        let file: String
        let line: Int
        let cases: Set<String>
        let ownConformances: Set<String>   // raw, from the enum's own inheritance clause
    }

    private var enums: [EnumInfo] = []

    /// Conformances added to a type via a separate `extension Foo: P {}`, keyed by the
    /// extended type's simple name. Merged with each enum's own conformances in Phase 2
    /// so a protocol adopted in an extension still counts as "already unified".
    private var extensionConformances: [String: Set<String>] = [:]

    // MARK: - Phase 1: collect

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        var caseNames: Set<String> = []
        var hasAssociatedValues = false
        for member in node.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                caseNames.insert(element.name.text)
                if element.parameterClause != nil { hasAssociatedValues = true }
            }
        }

        // Plain tag enums only: associated values make a case a constructor, not a label,
        // so the "same set of labels" comparison no longer means the same shape.
        guard !hasAssociatedValues, caseNames.count >= Self.minLabels else {
            return .visitChildren
        }

        var conformances: Set<String> = []
        if let inheritance = node.inheritanceClause {
            for inherited in inheritance.inheritedTypes {
                if let name = conformanceName(inherited.type) {
                    conformances.insert(name)
                }
            }
        }

        enums.append(EnumInfo(
            name: node.name.text,
            file: currentFilePath,
            line: getLineNumber(for: Syntax(node)),
            cases: caseNames,
            ownConformances: conformances
        ))
        return .visitChildren
    }

    /// Record protocol conformances declared in a separate `extension Foo: P {}` so
    /// they count toward the type being "already unified" in Phase 2.
    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let inheritance = node.inheritanceClause,
              let typeName = conformanceName(node.extendedType) else {
            return .visitChildren
        }
        var conformances: Set<String> = []
        for inherited in inheritance.inheritedTypes {
            if let name = conformanceName(inherited.type) {
                conformances.insert(name)
            }
        }
        if !conformances.isEmpty {
            extensionConformances[typeName, default: []].formUnion(conformances)
        }
        return .visitChildren
    }

    /// The simple name of a conformance/raw type, unwrapping attributes so isolated or
    /// attributed conformances (`@retroactive P`) resolve to `P`.
    private func conformanceName(_ type: TypeSyntax) -> String? {
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return conformanceName(attributed.baseType)
        }
        if let ident = type.as(IdentifierTypeSyntax.self) { return ident.name.text }
        if let member = type.as(MemberTypeSyntax.self) { return member.name.text }
        return nil
    }

    // MARK: - Phase 2: cluster + emit

    func finalizeAnalysis() {
        // Cluster by identical case-name set.
        var clusters: [String: [EnumInfo]] = [:]
        for info in enums {
            clusters[info.cases.sorted().joined(separator: "|"), default: []].append(info)
        }

        for cluster in clusters.values where cluster.count >= Self.minClusterSize {
            // Suppress when every member already shares a domain protocol — they are
            // unified, so there is nothing to suggest.
            let sharedProtocols = cluster.dropFirst().reduce(domainConformances(of: cluster[0])) {
                $0.intersection(domainConformances(of: $1))
            }
            guard sharedProtocols.isEmpty else { continue }

            let caseList = cluster[0].cases.sorted().joined(separator: ", ")
            let allNames = cluster.map(\.name).sorted()

            for info in cluster {
                let peers = allNames.filter { $0 != info.name }.joined(separator: ", ")
                addIssue(
                    severity: .info,
                    message: "`\(info.name)` declares the same \(info.cases.count) cases "
                        + "(\(caseList)) as \(peers) but they share no protocol.",
                    filePath: info.file,
                    lineNumber: info.line,
                    suggestion: "Consolidate \(allNames.joined(separator: ", ")) into one enum, "
                        + "or declare a shared protocol they all conform to — a natural home for "
                        + "any per-case mapping (see Scattered Enum Mapping).",
                    ruleName: .parallelEnumShape
                )
            }
        }
    }

    /// The enum's domain conformances: its own plus any added in a separate extension,
    /// minus ubiquitous raw-value types and standard protocols.
    private func domainConformances(of info: EnumInfo) -> Set<String> {
        info.ownConformances
            .union(extensionConformances[info.name] ?? [])
            .subtracting(Self.ubiquitousConformances)
    }
}

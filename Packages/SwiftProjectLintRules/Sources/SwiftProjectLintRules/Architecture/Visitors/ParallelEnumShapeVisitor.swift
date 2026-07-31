import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: flags two or more **name lists that are identical** — an implicit
/// "same concept, declared twice" that should be one declaration or a shared abstraction.
/// The structural twin of `ScatteredEnumMapping` and the analogue of `DuplicateStructShape`.
/// See `Docs/rules/parallel-enum-shape.md`.
///
/// Two carriers count as a name list:
///   - an `enum`'s case names (associated-value-free), and
///   - an array/set literal whose elements are uniformly name-like.
///
/// The array carrier exists because identical *arrays* were a blind spot across the whole
/// rule family: `ParallelListDrift` deliberately ignores similarity 1.0 (that is agreement,
/// not drift) and nothing else looked at literal lists, so two byte-identical hand-maintained
/// lists — the highest-risk pre-drift state there is — were invisible until the day someone
/// edited one of them. Found by dogfooding on this repository, where `primitiveCarriers` is
/// duplicated verbatim across two visitors.
///
/// **Phase 1 (walk):** catalog every enum's case-name set (plus whether it has associated
/// values and its non-ubiquitous conformances) and every name-like array literal.
/// **Phase 2 (`finalizeAnalysis`):** cluster by identical *normalized* name set, drop clusters
/// already unified by a shared domain protocol, then emit one issue per member.
final class ParallelEnumShapeVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    private static let minLabels = 3        // 2-case enums coincide too often (on/off, yes/no)
    private static let minClusterSize = 2   // need at least two lists to be "parallel"

    /// Array literals coincide far more readily than enums do — `["a", "b", "c"]` is not a
    /// concept — so the array carrier carries a higher floor than the enum one.
    private static let minArrayEntries = 5

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

    /// Which syntactic shape a list was read from — reported so the message names the right
    /// thing and suggests the right fix.
    private enum Carrier {
        case enumCases
        case arrayLiteral
    }

    private struct EnumInfo {
        let name: String
        let carrier: Carrier
        let file: String
        let line: Int
        let cases: Set<String>             // normalized, so `uiPatterns` == `"ui-patterns"`
        let display: [String: String]      // normalized → original spelling, for messages
        let ownConformances: Set<String>   // raw, from the enum's own inheritance clause

        /// Original spellings, sorted, for use in messages.
        var spellings: [String] {
            cases.map { display[$0] ?? $0 }.sorted()
        }
    }

    private var enums: [EnumInfo] = []

    /// Conformances added to a type via a separate `extension Foo: P {}`, keyed by the
    /// extended type's simple name. Merged with each enum's own conformances in Phase 2
    /// so a protocol adopted in an extension still counts as "already unified".
    private var extensionConformances: [String: Set<String>] = [:]

    // MARK: - Phase 1: collect

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        var caseNames: [String] = []
        var hasAssociatedValues = false
        for member in node.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                caseNames.append(element.name.text)
                if element.parameterClause != nil { hasAssociatedValues = true }
            }
        }

        // Plain tag enums only: associated values make a case a constructor, not a label,
        // so the "same set of labels" comparison no longer means the same shape.
        let (normalized, display) = Self.normalized(caseNames)
        guard !hasAssociatedValues, normalized.count >= Self.minLabels else {
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
            carrier: .enumCases,
            file: currentFilePath,
            line: getLineNumber(for: Syntax(node)),
            cases: normalized,
            display: display,
            ownConformances: conformances
        ))
        return .visitChildren
    }

    /// Collect array/set literals whose elements are uniformly name-like.
    ///
    /// Test and fixture files are excluded for this carrier only: a test that restates a
    /// production list verbatim is the expected shape there, not a duplication to fix. Enums
    /// keep their existing behaviour so the rule's established findings do not move.
    override func visit(_ node: ArrayExprSyntax) -> SyntaxVisitorContinueKind {
        guard !isTestOrFixtureFile(),
              let names = NameListReader.names(inArrayLiteral: node) else {
            return .visitChildren
        }
        let (normalized, display) = Self.normalized(names)
        guard normalized.count >= Self.minArrayEntries else { return .visitChildren }

        enums.append(EnumInfo(
            name: NameListReader.bindingName(of: node) ?? "array literal",
            carrier: .arrayLiteral,
            file: currentFilePath,
            line: getLineNumber(for: Syntax(node)),
            cases: normalized,
            display: display,
            ownConformances: []   // a literal has no conformances, so it is never "already unified"
        ))
        return .visitChildren
    }

    /// Normalizes names for comparison and keeps the first original spelling of each, so
    /// clustering is spelling-insensitive while messages stay readable.
    private static func normalized(_ raw: [String]) -> (Set<String>, [String: String]) {
        var names: Set<String> = []
        var display: [String: String] = [:]
        for original in raw {
            let key = NameListReader.normalize(original)
            guard !key.isEmpty else { continue }
            names.insert(key)
            if display[key] == nil { display[key] = original }
        }
        return (names, display)
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

            let caseList = cluster[0].spellings.joined(separator: ", ")
            let allNames = cluster.map(\.name).sorted()

            for info in cluster {
                // Identify peers by *location*, not by name. Filtering by name silently
                // produced an empty peer list whenever the cluster members shared one — two
                // `FilterType` enums, or two `expensiveOperations` arrays — which is exactly
                // the case where the reader most needs to be told where the other copy is.
                let peers = cluster
                    .filter { $0.file != info.file || $0.line != info.line }
                    .map { "`\($0.name)` (\(Self.shortName($0.file)):\($0.line))" }
                    .sorted()
                    .joined(separator: ", ")
                addIssue(
                    severity: .info,
                    message: message(for: info, peers: peers, count: info.cases.count, list: caseList),
                    filePath: info.file,
                    lineNumber: info.line,
                    suggestion: suggestion(for: cluster, allNames: allNames),
                    ruleName: .parallelEnumShape
                )
            }
        }
    }

    /// The finding, phrased for the carrier it was read from. An enum "declares cases"; a
    /// literal list "declares entries", and saying so is the difference between a message a
    /// reader can act on and one they have to decode.
    private func message(for info: EnumInfo, peers: String, count: Int, list: String) -> String {
        switch info.carrier {
        case .enumCases:
            return "`\(info.name)` declares the same \(count) cases (\(list)) as \(peers) "
                + "but they share no protocol."

        case .arrayLiteral:
            return "`\(info.name)` declares the same \(count) entries (\(list)) as \(peers) — "
                + "the same list maintained in more than one place."
        }
    }

    /// A cluster of literal lists wants consolidation into one declaration; a cluster of enums
    /// additionally has the shared-protocol option, and a natural home for per-case mappings.
    private func suggestion(for cluster: [EnumInfo], allNames: [String]) -> String {
        let names = Array(Set(allNames)).sorted().joined(separator: ", ")
        if cluster.allSatisfy({ $0.carrier == .arrayLiteral }) {
            return "Declare \(names) once and reference the single copy. They agree today, so "
                + "nothing is broken yet — that is precisely why this is the cheap moment to fix "
                + "it, before an entry is added to one and not the others (see Parallel List Drift)."
        }
        return "Consolidate \(names) into one enum, or declare a shared protocol they all "
            + "conform to — a natural home for any per-case mapping (see Scattered Enum Mapping)."
    }

    private static func shortName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    /// The enum's domain conformances: its own plus any added in a separate extension,
    /// minus ubiquitous raw-value types and standard protocols.
    private func domainConformances(of info: EnumInfo) -> Set<String> {
        info.ownConformances
            .union(extensionConformances[info.name] ?? [])
            .subtracting(Self.ubiquitousConformances)
    }
}

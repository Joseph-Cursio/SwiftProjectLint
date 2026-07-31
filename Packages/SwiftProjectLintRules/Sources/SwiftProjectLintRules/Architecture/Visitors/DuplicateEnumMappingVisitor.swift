import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: flags two (or more) `switch`es over the same enum that produce the
/// **exact same** case→value mapping — one function written twice. See
/// `Docs/rules/duplicate-enum-mapping.md`.
///
/// This is the strict sibling of `Scattered Enum Mapping`. That rule matches loosely (by
/// case-set + return *kind*) and so needs >= 3 scattered sites before it dares fire — two
/// switches over `Severity` both returning *some* `Color` might be a foreground map and a
/// background map. This rule matches by the **literal value returned for each case**: when
/// the value maps are identical there is no benign reading — it is the same mapping copied —
/// so **two sites are enough**. The two rules are complements: loose match / high threshold
/// finds a *missing abstraction*; exact match / low threshold finds a *copied function*.
///
/// **Phase 1 (walk):** catalog enums (name → case-name set) and collect "mapping switches" —
/// >= `minLabels` leading-dot `case .x:` arms whose bodies are each a single literal / member /
/// initializer expression — capturing the `case-label → value-text` map of each.
/// **Phase 2 (`finalizeAnalysis`):** group sites by their full value map and emit when a group
/// has >= `minSites` sites in >= `minDistinctSites` distinct source locations. When one member
/// of the group is the enum's own `switch self` mapping, the others are reported as duplicating
/// it (and pointed at it); otherwise the group is reported as an un-extracted copied mapping.
final class DuplicateEnumMappingVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    // Tunable thresholds — compile-time constants, matching the sibling visitors.
    private static let minLabels = 3   // 2-case switches map by coincidence; bias to specific enums
    private static let minSites = 2    // exact-value match makes a *pair* conclusive

    /// One enum→value mapping `switch`, reduced to the value it returns per case.
    private struct MappingSite {
        let caseValues: [String: String]   // case label → trimmed value-expression text
        let defaultValue: String?          // value text of a `default:` arm, if any
        let file: String
        let line: Int
        let enclosingType: String?         // nearest enum / type / extension name, if any
        let isSelfSubject: Bool            // `switch self { … }`

        /// The set of case labels this mapping covers.
        var labels: Set<String> { Set(caseValues.keys) }
    }

    private var sites: [MappingSite] = []
    /// Enum simple name → its case-name set. Used to name the subject enum(s) in Phase 2.
    private var enumCases: [String: Set<String>] = [:]
    /// Stack of enclosing nominal-type / extension names, innermost last.
    private var typeStack: [String] = []

    // MARK: - Phase 1: enclosing-type tracking

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let names = node.memberBlock.members.flatMap { member -> [String] in
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { return [] }
            return caseDecl.elements.map(\.name.text)
        }
        if !names.isEmpty {
            enumCases[node.name.text] = Set(names)
        }
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ _: EnumDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text); return .visitChildren
    }
    override func visitPost(_ _: StructDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text); return .visitChildren
    }
    override func visitPost(_ _: ClassDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text); return .visitChildren
    }
    override func visitPost(_ _: ActorDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(simpleTypeName(node.extendedType)); return .visitChildren
    }
    override func visitPost(_ _: ExtensionDeclSyntax) { typeStack.removeLast() }

    // MARK: - Phase 1: mapping-switch collection

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        if let site = mappingSite(from: node) {
            sites.append(site)
        }
        return .visitChildren
    }

    /// Returns a `MappingSite` when `node` is a clean enum→value mapping: every arm is a
    /// single literal / member / initializer expression, and there are at least `minLabels`
    /// `.case` labels. Returns nil otherwise.
    private func mappingSite(from node: SwitchExprSyntax) -> MappingSite? {
        var caseValues: [String: String] = [:]
        var defaultValue: String?

        for element in node.cases {
            guard let switchCase = element.as(SwitchCaseSyntax.self),
                  let value = singleExpressionBody(switchCase.statements),
                  isValueExpression(value) else { return nil }
            let valueText = value.trimmedDescription

            switch switchCase.label {
            case .case(let caseLabel):
                for item in caseLabel.caseItems {
                    guard let label = enumCaseLabel(item.pattern) else { return nil }
                    caseValues[label] = valueText
                }

            case .default:
                defaultValue = valueText

            @unknown default:
                return nil
            }
        }

        guard caseValues.count >= Self.minLabels else { return nil }

        return MappingSite(
            caseValues: caseValues,
            defaultValue: defaultValue,
            file: currentFilePath,
            line: getLineNumber(for: Syntax(node)),
            enclosingType: typeStack.last,
            isSelfSubject: node.subject.trimmedDescription == "self"
        )
    }

    /// The bare enum-constant name of a `case .x:` pattern (`.error` → "error"), or nil for
    /// value-binding / associated-value / non-member patterns — those aren't pure constant maps.
    private func enumCaseLabel(_ pattern: PatternSyntax) -> String? {
        guard let exprPattern = pattern.as(ExpressionPatternSyntax.self),
              let member = exprPattern.expression.as(MemberAccessExprSyntax.self),
              member.base == nil else { return nil }
        return member.declName.baseName.text
    }

    /// The single result expression of a switch arm — the `return X` form or the implicit-return
    /// `X` switch-expression form. Nil for empty, multi-statement, or non-expression bodies.
    private func singleExpressionBody(_ statements: CodeBlockItemListSyntax) -> ExprSyntax? {
        guard statements.count == 1, let only = statements.first else { return nil }
        switch only.item {
        case .expr(let expr): return expr
        case .stmt(let stmt): return stmt.as(ReturnStmtSyntax.self)?.expression
        default: return nil
        }
    }

    /// Whether `expr` is a value the mapping returns — a string / int / float literal, a bare or
    /// type-qualified member (`.red`, `Color.red`), or a named initializer/factory call
    /// (`Color(...)`). Arbitrary expressions (function calls on lowercase callees, operators,
    /// interpolations, …) are not a constant map and disqualify the switch — the same gate
    /// `Scattered Enum Mapping` uses, so the two rules recognise the same shape.
    private func isValueExpression(_ expr: ExprSyntax) -> Bool {
        if expr.is(StringLiteralExprSyntax.self)
            || expr.is(IntegerLiteralExprSyntax.self)
            || expr.is(FloatLiteralExprSyntax.self) {
            return true
        }
        if let call = expr.as(FunctionCallExprSyntax.self) {
            return initializerTypeName(call.calledExpression) != nil
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            if member.base == nil { return true }   // .red
            if let base = member.base?.as(DeclReferenceExprSyntax.self) {
                return base.baseName.text.first?.isUppercase == true   // Color.red
            }
        }
        return false
    }

    /// The named type of an initializer/static-factory callee — `Color(...)` → "Color",
    /// `Color.dynamic(...)` → "Color" — or nil for a leading-dot / non-type callee.
    private func initializerTypeName(_ callee: ExprSyntax) -> String? {
        if let ref = callee.as(DeclReferenceExprSyntax.self),
           ref.baseName.text.first?.isUppercase == true {
            return ref.baseName.text
        }
        if let member = callee.as(MemberAccessExprSyntax.self),
           let base = member.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text.first?.isUppercase == true {
            return base.baseName.text
        }
        return nil
    }

    private func simpleTypeName(_ type: TypeSyntax) -> String {
        if let ident = type.as(IdentifierTypeSyntax.self) { return ident.name.text }
        if let member = type.as(MemberTypeSyntax.self) { return member.name.text }
        return type.trimmedDescription
    }

    // MARK: - Phase 2: group + emit

    func finalizeAnalysis() {
        var groups: [String: [MappingSite]] = [:]
        for site in sites {
            groups[groupKey(for: site), default: []].append(site)
        }

        for group in groups.values {
            // Distinct source locations — the same switch is never counted twice.
            let distinct = dedupedByLocation(group)
            guard distinct.count >= Self.minSites else { continue }

            let reference = distinct[0]
            let subjects = subjectEnums(for: reference.labels)
            let enumPhrase = subjectPhrase(subjects, labels: reference.labels)
            let valuePhrase = "the same value for every case"

            // If one site is the enum's own `switch self` mapping, it is the canonical home;
            // the others duplicate it and should call it.
            let canonical = distinct.first(where: { isCentralized($0) })

            for site in distinct where !(canonical.map { isSameLocation($0, site) } ?? false) {
                let peers = distinct
                    .filter { !isSameLocation($0, site) }
                    .map { "\(shortName($0.file)):\($0.line)" }
                    .sorted()
                    .joined(separator: ", ")

                let message: String
                let suggestion: String
                if let canonical {
                    message = "This \(enumPhrase) → value mapping is identical to the one already "
                        + "on the type (\(shortName(canonical.file)):\(canonical.line)); it maps "
                        + "\(valuePhrase) the same way, so it is that mapping copied."
                    suggestion = "Delete this switch and call the mapping on `"
                        + (subjects.first ?? "the enum") + "` instead."
                } else {
                    message = "This \(enumPhrase) → value mapping is written identically in "
                        + "\(distinct.count) places (peers: \(peers)) — the same function copied, "
                        + "not two different mappings."
                    suggestion = "Extract the mapping to one computed property on the enum "
                        + "(or an extension) and call it from each site."
                }

                addIssue(
                    severity: .info,
                    message: message,
                    filePath: site.file,
                    lineNumber: site.line,
                    suggestion: suggestion,
                    ruleName: .duplicateEnumMapping
                )
            }
        }
    }

    /// A stable key for a site's full value map: the sorted `label:value` pairs plus any
    /// `default:` value. Two sites share a key iff they map every case to identical value text.
    private func groupKey(for site: MappingSite) -> String {
        let pairs = site.caseValues
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "|")
        return pairs + "##default=" + (site.defaultValue ?? "")
    }

    /// Collapse sites that share a source location (defensive — one switch is walked once, but a
    /// file re-analysed would otherwise double-count).
    private func dedupedByLocation(_ group: [MappingSite]) -> [MappingSite] {
        var seen: Set<String> = []
        var result: [MappingSite] = []
        for site in group where seen.insert("\(site.file):\(site.line)").inserted {
            result.append(site)
        }
        return result
    }

    private func isSameLocation(_ lhs: MappingSite, _ rhs: MappingSite) -> Bool {
        lhs.file == rhs.file && lhs.line == rhs.line
    }

    /// A site is the centralized (canonical) mapping when it switches `self` inside the very
    /// enum whose cases it maps — the single source of truth the duplicates should call.
    private func isCentralized(_ site: MappingSite) -> Bool {
        guard site.isSelfSubject, let enclosing = site.enclosingType else { return false }
        return enumCases[enclosing] == site.labels
    }

    private func subjectEnums(for labels: Set<String>) -> [String] {
        enumCases.filter { $0.value == labels }.map(\.key)
    }

    private func subjectPhrase(_ subjects: [String], labels: Set<String>) -> String {
        switch subjects.count {
        case 0:
            return "enum (cases \(labels.sorted().joined(separator: ", ")))"
        case 1:
            return "`\(subjects[0])`"
        default:
            return "enum \(subjects.sorted().map { "`\($0)`" }.joined(separator: " / "))"
        }
    }

    private func shortName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

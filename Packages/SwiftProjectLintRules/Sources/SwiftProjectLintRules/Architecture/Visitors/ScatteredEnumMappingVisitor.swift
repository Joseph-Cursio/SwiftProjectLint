import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: flags the same enum being exhaustively `switch`ed in several
/// places, each arm returning a literal/initializer of one uniform kind — a single
/// mapping copy-pasted instead of centralized on the type. The behavioral analogue
/// of `DuplicateStructShape`. See `Docs/rules/scattered-enum-mapping.md`.
///
/// **Phase 1 (walk):** catalog enums (name → case-name set) and collect "mapping
/// switches" — those with >= `minLabels` leading-dot `case .x:` arms whose bodies are
/// all single expressions of a uniform return kind.
/// **Phase 2 (`finalizeAnalysis`):** group mapping sites by (case-label set, return
/// kind), and emit when a group has >= `minSites` *scattered* sites across >= `minFiles`
/// files. A switch-on-`self` inside the enum/its extension is the centralized form and
/// is never counted as scatter — its presence only changes the message.
final class ScatteredEnumMappingVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    // Tunable thresholds — compile-time constants, matching the convention used by the
    // other Architecture cross-file visitors (`DuplicateStructShape.minimumShared`).
    private static let minLabels = 3   // 2-case enums map by coincidence; bias to specific enums
    private static let minSites = 3    // fewer than three copies is not yet a pattern
    private static let minFiles = 2    // the cross-file requirement is the whole point

    /// A single hand-written enum→value mapping switch.
    private struct MappingSite {
        let labels: Set<String>            // the `.case` labels switched over
        let returnKind: String             // uniform kind of every arm body (see classify)
        let members: [String]              // for `implicit-member` kind: the sorted `.member` set
        let file: String
        let line: Int
        let enclosingType: String?         // nearest enum / extension type name, if any
        let isSelfSubject: Bool            // `switch self { … }`
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
            return caseDecl.elements.map { $0.name.text }
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
        guard let site = mappingSite(from: node) else { return .visitChildren }
        sites.append(site)
        return .visitChildren
    }

    /// Returns a `MappingSite` when `node` is a clean enum→literal mapping: every arm
    /// (case and `default`) is a single expression of one uniform return kind, and there
    /// are at least `minLabels` `.case` labels. Returns nil otherwise.
    private func mappingSite(from node: SwitchExprSyntax) -> MappingSite? {
        var labels: Set<String> = []
        var kinds: Set<String> = []
        var members: Set<String> = []

        for element in node.cases {
            guard let switchCase = element.as(SwitchCaseSyntax.self) else { return nil }

            // Body must be a single expression (`return X` or implicit-return `X`).
            guard let value = singleExpressionBody(switchCase.statements),
                  let (kind, member) = classify(value) else { return nil }
            kinds.insert(kind)
            if let member { members.insert(member) }

            switch switchCase.label {
            case .case(let caseLabel):
                for item in caseLabel.caseItems {
                    guard let label = enumCaseLabel(item.pattern) else { return nil }
                    labels.insert(label)
                }

            case .default:
                break   // default contributes no label but its body is still kind-checked

            @unknown default:
                return nil
            }
        }

        guard labels.count >= Self.minLabels, kinds.count == 1, let kind = kinds.first else {
            return nil
        }

        return MappingSite(
            labels: labels,
            returnKind: kind,
            members: members.sorted(),
            file: currentFilePath,
            line: getLineNumber(for: Syntax(node)),
            enclosingType: typeStack.last,
            isSelfSubject: node.subject.trimmedDescription == "self"
        )
    }

    /// The bare enum-constant name of a `case .x:` pattern (`.error` → "error"), or nil
    /// for value-binding / associated-value / non-member patterns — those aren't pure
    /// constant maps and disqualify the switch.
    private func enumCaseLabel(_ pattern: PatternSyntax) -> String? {
        guard let exprPattern = pattern.as(ExpressionPatternSyntax.self),
              let member = exprPattern.expression.as(MemberAccessExprSyntax.self),
              member.base == nil else { return nil }
        return member.declName.baseName.text
    }

    /// Extracts the single result expression of a switch arm, handling both the
    /// `return X` form and the implicit-return `X` switch-expression form. Returns nil
    /// for empty, multi-statement, or non-expression bodies (e.g. `throw`).
    private func singleExpressionBody(_ statements: CodeBlockItemListSyntax) -> ExprSyntax? {
        guard statements.count == 1, let only = statements.first else { return nil }
        switch only.item {
        case .expr(let expr):
            return expr

        case .stmt(let stmt):
            return stmt.as(ReturnStmtSyntax.self)?.expression

        default:
            return nil
        }
    }

    /// Coarse, type-free classification of an arm body. Returns the uniform "kind" key
    /// plus, for the weak `implicit-member` kind, the member name so Phase 2 can require
    /// the member set to match across sites. Returns nil for non-literal expressions.
    private func classify(_ expr: ExprSyntax) -> (kind: String, member: String?)? {
        if expr.is(StringLiteralExprSyntax.self) { return ("String", nil) }
        if expr.is(IntegerLiteralExprSyntax.self) { return ("Int", nil) }
        if expr.is(FloatLiteralExprSyntax.self) { return ("Double", nil) }

        if let call = expr.as(FunctionCallExprSyntax.self) {
            if let typeName = initializerTypeName(call.calledExpression) {
                return (typeName, nil)
            }
            return nil
        }

        if let member = expr.as(MemberAccessExprSyntax.self) {
            if let base = member.base?.as(DeclReferenceExprSyntax.self),
               base.baseName.text.first?.isUppercase == true {
                return (base.baseName.text, nil)   // Color.red, Font.title
            }
            if member.base == nil {
                return ("implicit-member", member.declName.baseName.text)   // .red, .orange
            }
        }
        return nil
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
            let scattered = group.filter { !isCentralized($0) }
            let files = Set(scattered.map(\.file))
            guard scattered.count >= Self.minSites, files.count >= Self.minFiles else { continue }

            let reference = group[0]
            let hasCentralized = group.contains { isCentralized($0) }
            let subjects = subjectEnums(for: reference.labels)
            let enumPhrase = subjectPhrase(subjects, labels: reference.labels)
            let returnPhrase = returnPhrase(for: reference)
            let twinNote = subjects.count >= 2
                ? " The same mapping is duplicated across enums with identical cases "
                    + "(\(subjects.sorted().joined(separator: ", "))); consider unifying them or a "
                    + "shared protocol (see Parallel Enum Shape)."
                : ""

            for site in scattered {
                let peers = scattered
                    .filter { $0.file != site.file || $0.line != site.line }
                    .map { "\(shortName($0.file)):\($0.line)" }
                    .sorted()
                    .joined(separator: ", ")

                let message: String
                let suggestion: String
                if hasCentralized {
                    message = "This re-implements the \(enumPhrase) → \(returnPhrase) mapping that "
                        + "already exists on the type; \(scattered.count) scattered copies remain "
                        + "(peers: \(peers))."
                    suggestion = "Call the existing computed mapping on the enum instead of "
                        + "re-switching." + twinNote
                } else {
                    message = "\(enumPhrase) is mapped to \(returnPhrase) by hand in "
                        + "\(scattered.count) places (peers: \(peers)) with no centralized mapping."
                    suggestion = "Move the mapping into a single computed property on the enum "
                        + "(or an extension) and call it from each site." + twinNote
                }

                addIssue(
                    severity: .info,
                    message: message,
                    filePath: site.file,
                    lineNumber: site.line,
                    suggestion: suggestion,
                    ruleName: .scatteredEnumMapping
                )
            }
        }
    }

    private func groupKey(for site: MappingSite) -> String {
        let labels = site.labels.sorted().joined(separator: "|")
        let memberSuffix = site.returnKind == "implicit-member"
            ? "##" + site.members.joined(separator: ",")
            : ""
        return "\(labels)##\(site.returnKind)\(memberSuffix)"
    }

    /// A site is the centralized (good) mapping when it switches `self` inside the very
    /// enum whose cases it maps — that is the single source of truth, not a scattered copy.
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
            return "An enum (cases \(labels.sorted().joined(separator: ", ")))"

        case 1:
            return "`\(subjects[0])`"

        default:
            return "Enums \(subjects.sorted().map { "`\($0)`" }.joined(separator: " / "))"
        }
    }

    private func returnPhrase(for site: MappingSite) -> String {
        if site.returnKind == "implicit-member" {
            return "a uniform value (`." + site.members.joined(separator: "`, `.") + "`)"
        }
        return "`\(site.returnKind)`"
    }

    private func shortName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

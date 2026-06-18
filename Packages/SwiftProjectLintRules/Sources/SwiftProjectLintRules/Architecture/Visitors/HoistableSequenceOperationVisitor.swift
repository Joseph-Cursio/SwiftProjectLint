import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor: flags an identical closure passed to a `Sequence` higher-order
/// method at two or more call sites, where the closure accesses *two or more* members
/// off its element and that member set is a subset of some project protocol `P`'s
/// property requirements. Such a closure is a candidate to become a
/// `extension Sequence where Element: P` helper, written once.
/// See `Docs/rules/hoistable-sequence-operation.md`.
///
/// This is the narrow, measured variant of the call-site half of "could hoist to a
/// protocol extension". A syntactic linter cannot resolve the element type of the
/// receiver, so it cannot prove `Element: P`. The two-member floor is the precision
/// gate: a measurement over real codebases found single-member closures (`{ $0.name … }`)
/// to be overwhelmingly false — `name` subsets a protocol by coincidence — while
/// two-member access sets like `{ category, name }` were 100% genuine. The suggestion is
/// therefore phrased conditionally ("if these hold `Element: P`").
///
/// **Phase 1 (walk):** record protocol property requirements, and every HOF closure site
/// with the members it touches and a normalized body.
/// **Phase 2 (`finalizeAnalysis`):** group sites by body; a group of `>= minimumSites`
/// whose `>= minimumMembers`-sized member set fits a protocol fires once per site.
final class HoistableSequenceOperationVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// Element-wise `Sequence` higher-order methods whose closure reads the element.
    private static let hofNames: Set<String> = [
        "sorted", "sort", "filter", "min", "max", "first", "last", "contains",
        "firstIndex", "lastIndex", "partition", "allSatisfy", "drop", "prefix"
    ]

    /// Two members is the precision gate (see type doc); one-member sets are dropped.
    private static let minimumMembers = 2
    /// The rule is about de-duplication, so the closure must recur.
    private static let minimumSites = 2

    private struct Site {
        let members: Set<String>
        let memberList: [String]
        let bodyKey: String
        let file: String
        let line: Int
    }

    private var sites: [Site] = []
    private var protocolRequirements: [String: Set<String>] = [:]

    // MARK: - Phase 1: collect

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        var names: Set<String> = []
        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                if let id = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                    names.insert(id)
                }
            }
        }
        protocolRequirements[node.name.text, default: []].formUnion(names)
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Form 1: receiver.hof { … } / receiver.hof(by: { … })
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
           Self.hofNames.contains(member.declName.baseName.text),
           let closure = closureArgument(of: node) {
            record(closure)
        }

        // Form 2: Dictionary(grouping: x, by: { … })
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self),
           callee.baseName.text == "Dictionary",
           let closure = node.arguments.first(where: { $0.label?.text == "by" })?
               .expression.as(ClosureExprSyntax.self) ?? node.trailingClosure {
            record(closure)
        }

        return .visitChildren
    }

    private func closureArgument(of node: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        if let trailing = node.trailingClosure { return trailing }
        return node.arguments.lazy.compactMap { $0.expression.as(ClosureExprSyntax.self) }.first
    }

    private func record(_ closure: ClosureExprSyntax) {
        let members = accessedMembers(in: closure)
        guard members.isEmpty == false else { return }
        sites.append(Site(
            members: members,
            memberList: members.sorted(),
            bodyKey: String(closure.trimmedDescription.filter { !$0.isWhitespace }),
            file: currentFilePath,
            line: getLineNumber(for: Syntax(closure))
        ))
    }

    /// Members accessed off the closure's parameter(s) — `$0.category`, `a.name`. Parameter
    /// names are taken from the signature (identifier tokens before `in`) plus the `$N`
    /// shorthand. Over-collecting parameter names is harmless: a non-parameter base simply
    /// contributes no protocol-relevant member.
    private func accessedMembers(in closure: ClosureExprSyntax) -> Set<String> {
        var paramNames: Set<String> = []
        if let signature = closure.signature {
            for token in signature.tokens(viewMode: .sourceAccurate) {
                if case .identifier = token.tokenKind { paramNames.insert(token.text) }
            }
        }
        let collector = ClosureMemberAccessCollector(paramNames: paramNames)
        collector.walk(closure)
        return collector.members
    }

    // MARK: - Phase 2: group + emit

    func finalizeAnalysis() {
        let groups = Dictionary(grouping: sites) { $0.bodyKey }
        for group in groups.values {
            guard group.count >= Self.minimumSites, let sample = group.first else { continue }
            guard sample.members.count >= Self.minimumMembers else { continue }
            guard let proto = hoistTarget(for: sample.members) else { continue }

            let memberText = sample.memberList.joined(separator: ", ")
            for site in group {
                addIssue(
                    severity: .info,
                    message: "A closure over '\(memberText)' recurs at \(group.count) call sites "
                        + "and touches only requirements of '\(proto)'.",
                    filePath: site.file,
                    lineNumber: site.line,
                    suggestion: "If these collections hold 'Element: \(proto)', hoist the closure "
                        + "into an 'extension Sequence where Element: \(proto)' helper so the "
                        + "operation is written once.",
                    ruleName: .hoistableSequenceOperation
                )
            }
        }
    }

    /// The most specific protocol (fewest requirements) whose property requirements cover
    /// the member set, or `nil` if none does.
    private func hoistTarget(for members: Set<String>) -> String? {
        protocolRequirements
            .filter { $0.value.isEmpty == false && members.isSubset(of: $0.value) }
            .min { lhs, rhs in
                lhs.value.count == rhs.value.count ? lhs.key < rhs.key : lhs.value.count < rhs.value.count
            }?
            .key
    }
}

/// Collects member accesses whose base is a closure parameter (`$N` or a named param).
private final class ClosureMemberAccessCollector: SyntaxVisitor {
    private let paramNames: Set<String>
    private(set) var members: Set<String> = []

    init(paramNames: Set<String>) {
        self.paramNames = paramNames
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        if let base = node.base?.as(DeclReferenceExprSyntax.self) {
            let text = base.baseName.text
            if text.hasPrefix("$") || paramNames.contains(text) {
                members.insert(node.declName.baseName.text)
            }
        }
        return .visitChildren
    }
}

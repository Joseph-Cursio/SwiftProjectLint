import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// An operand of an `||` or `&&` chain that can never change its result, because another operand
/// implies it or is implied by it.
///
///     tagDescription.contains("int") || tagDescription.contains("tag:yaml.org,2002:int")
///
/// The second test implies the first, so whenever it is true the chain already is. It reads like
/// a second chance to match and is dead weight, and it usually marks a mistake in the *other*
/// operand: the precise test states the intent, and the loose one matches more than intended —
/// `contains("int")` also accepts `"!hint"` and `"!point"`.
///
/// ## Why this rule exists
///
/// Mutation testing found it. On SwiftLintRuleStudio, every `||` → `&&` mutant of the three YAML
/// scalar classifiers (`isBoolScalar`, `isIntScalar`, `isFloatScalar`) survived, as did both in
///
///     if trimmed.isEmpty || trimmed.hasPrefix("+") || !trimmed.hasPrefix("|") { return false }
///
/// where an empty line and a `+` line already fail to start with `|`, so the condition is
/// `!trimmed.hasPrefix("|")`. No test can kill those mutants: they change an operand that never
/// decides anything. They are *equivalent*, and a mutation report that lists them sends someone
/// to write a test that cannot exist. Naming the redundancy at the source says what the report
/// cannot.
///
/// ## What is read
///
/// Each operand of a flat chain — one connective throughout — or of an `if`/`guard` condition
/// list (an `&&` by another spelling) is read as a `StringTestAtom` when it is an equality,
/// `contains`, `hasPrefix`, `hasSuffix` or `isEmpty` test against a literal, or the negation of
/// one. Implication is decided from the literals alone, and anything else is opaque: an opaque
/// operand implies nothing, so the rule never reports a redundancy it has not proved.
///
/// In an `||`, an operand that implies another is redundant. In an `&&`, one implied by another
/// is.
final class SubsumedConditionVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        var connectives: Set<String> = []
        var operands: [[ExprSyntax]] = [[]]
        for element in node.elements {
            if element.is(UnresolvedTernaryExprSyntax.self) || element.is(AssignmentExprSyntax.self) {
                return .visitChildren
            }
            if let connective = element.as(BinaryOperatorExprSyntax.self)?.operator.text,
               connective == "||" || connective == "&&" {
                connectives.insert(connective)
                operands.append([])
            } else {
                operands[operands.count - 1].append(element)
            }
        }
        guard connectives.count == 1, let connective = connectives.first, operands.count >= 2 else {
            return .visitChildren
        }
        report(operands.map(StringTestAtom.read), connective: connective, node: Syntax(node))
        return .visitChildren
    }

    override func visit(_ node: ConditionElementListSyntax) -> SyntaxVisitorContinueKind {
        guard node.count >= 2 else { return .visitChildren }
        let atoms = node.map { element -> StringTestAtom? in
            guard case .expression(let expr) = element.condition else { return nil }
            if let sequence = expr.as(SequenceExprSyntax.self) {
                return StringTestAtom.read(Array(sequence.elements))
            }
            return StringTestAtom.read([expr])
        }
        report(atoms, connective: "&&", node: Syntax(node))
        return .visitChildren
    }

    /// Reports each operand that cannot change the chain, latest first, so of two that imply each
    /// other — a duplicate — the second is the one named.
    private func report(_ parsed: [StringTestAtom?], connective: String, node: Syntax) {
        guard parsed.compactMap(\.self).count >= 2 else { return }
        let proven = Set(parsed.compactMap(\.self).filter(\.provesString).map(\.receiver))
        var evidence: [String: Bool] = [:]
        let atoms = parsed.map { atom -> StringTestAtom? in
            guard var atom else { return nil }
            atom.receiverIsString = proven.contains(atom.receiver) || {
                if let known = evidence[atom.receiver] { return known }
                let known = StringReceiverEvidence.isString(atom.receiver, at: node)
                evidence[atom.receiver] = known
                return known
            }()
            return atom
        }
        var live = Array(atoms.indices)
        for index in atoms.indices.reversed() {
            guard let atom = atoms[index] else { continue }
            let witness = live.first { other in
                guard other != index, let candidate = atoms[other] else { return false }
                return connective == "||" ? atom.implies(candidate) : candidate.implies(atom)
            }
            guard let witness, let other = atoms[witness] else { continue }
            live.removeAll { $0 == index }
            addIssue(
                severity: .info,
                message: Self.message(redundant: atom, witness: other, connective: connective),
                filePath: getFilePath(for: node),
                lineNumber: getLineNumber(for: node),
                suggestion: Self.suggestion,
                ruleName: .subsumedCondition
            )
        }
    }

    private static func message(
        redundant: StringTestAtom,
        witness: StringTestAtom,
        connective: String
    ) -> String {
        let reason = connective == "||"
            ? "it implies `\(spelling(of: witness))`, so whenever it holds the chain already does"
            : "`\(spelling(of: witness))` implies it, so whenever the chain reaches it, it holds"
        return "`\(spelling(of: redundant))` can never change this `\(connective)`: \(reason)."
    }

    static let suggestion = "Delete the operand that cannot decide anything — or, if it is the "
        + "precise one and states the intent, narrow the other: a loose test that subsumes a "
        + "precise one usually matches more than was meant. Until then, mutation testing reports "
        + "this operand's operator mutants as survivors no test can kill."

    /// The atom as a reader would write it.
    static func spelling(of atom: StringTestAtom) -> String {
        let receiver = atom.receiver
        let text: String
        switch atom.kind {
        case .equals(let value): return "\(receiver) \(atom.negated ? "!=" : "==") \"\(value)\""
        case .contains(let value): text = "\(receiver).contains(\"\(value)\")"
        case .prefix(let value): text = "\(receiver).hasPrefix(\"\(value)\")"
        case .suffix(let value): text = "\(receiver).hasSuffix(\"\(value)\")"
        case .isEmpty: text = "\(receiver).isEmpty"
        }
        return atom.negated ? "!\(text)" : text
    }
}

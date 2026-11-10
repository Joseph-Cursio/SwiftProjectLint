import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A predicate body that makes no decision — it reads a `Bool` and hands it back.
///
/// `{ $0.isEnabled }`, `{ !$0.isHidden }`, `{ $0.file.isFolder }`: a plain member path off the
/// closure's own parameter, optionally negated. Nothing is being *decided* here, only surfaced, and a
/// stored property cannot disagree with itself. There is no law to state, and nothing to generate
/// inputs against.
///
/// The moment anything else appears — a `&&`, a comparison, a call, a branch — a *rule* is being
/// expressed, and a rule is a thing that can be subtly wrong:
///
///     { $0.path.hasPrefix(parent) && $0.path != parent }
///
/// That is one line, and it is one off-by-one from wrong. The old size floor of two statements dropped
/// it silently, which is precisely the mistake the comparators had already taught.
///
/// **It errs towards firing, deliberately and symmetrically with `FreeOrdering`.** A predicate reached
/// through a call — `{ $0.name.hasPrefix("_") }` — is reported, because the analyser cannot see that
/// the call is total, and the interesting predicates in real code are call-shaped
/// (`localizedCaseInsensitiveContains(query)`, and every locale bug that lives in one).
enum FreeDecision {

    static func describes(_ closure: ClosureExprSyntax) -> Bool {
        guard closure.statements.count == 1,
              let expression = ClosureBody.soleExpression(of: closure) else {
            return false
        }

        let body = withoutNegation(expression)

        // `{ $0.isEnabled }` — a stored Bool, surfaced.
        if ClosureBody.memberPath(of: body) != nil { return true }

        // `{ $0 == fileURL }` — identity, not a rule.
        return isPlainEquality(body)
    }

    /// An equality between two plain operands: `{ $0 == fileURL }`, `{ $0.status == .uploading }`.
    ///
    /// This is **identity, not a decision.** `Equatable` already guarantees everything there is to
    /// guarantee about it, there is no law left to state, and there is no off-by-one for a generator
    /// to find — `removeAll { $0 == fileURL }` means "remove this element" and nothing more.
    ///
    /// A *relational* comparison is a different matter and still fires. `{ $0.count > 0 }` and
    /// `{ $0.updated < $0.created }` express thresholds and orderings, and those are exactly the
    /// decisions that come out one boundary wrong.
    static func isPlainEquality(_ expression: ExprSyntax) -> Bool {
        guard let comparison = Comparison(expression),
              comparison.symbol == "==" || comparison.symbol == "!=" else {
            return false
        }
        return isPlainOperand(comparison.left) && isPlainOperand(comparison.right)
    }

    /// A stored path (`$0.status`), an implicit member (`.uploading`), or a literal. Anything else —
    /// a call above all — is doing work, and work can be wrong.
    static func isPlainOperand(_ expression: ExprSyntax) -> Bool {
        if ClosureBody.memberPath(of: expression) != nil { return true }

        // `.uploading` — an implicit member reference has no base, so it has no member path.
        if let member = expression.as(MemberAccessExprSyntax.self), member.base == nil { return true }

        return expression.is(StringLiteralExprSyntax.self)
            || expression.is(IntegerLiteralExprSyntax.self)
            || expression.is(FloatLiteralExprSyntax.self)
            || expression.is(BooleanLiteralExprSyntax.self)
            || expression.is(NilLiteralExprSyntax.self)
    }

    /// `!$0.isHidden` decides nothing that `$0.isHidden` does not.
    static func withoutNegation(_ expression: ExprSyntax) -> ExprSyntax {
        guard let prefixed = expression.as(PrefixOperatorExprSyntax.self),
              prefixed.operator.text == "!" else {
            return expression
        }
        return prefixed.expression
    }
}

/// A comparator body whose ordering comes for free from the key's `Comparable` conformance.
///
/// The shape is exactly `<lhs><path> < <rhs><path>` (or `>`) — one strict comparison, the same member
/// path on both sides, the two closure parameters as the two bases. `{ $0 < $1 }` qualifies with an
/// empty path.
///
/// **Deliberately syntactic, and it errs towards firing.** A key reached through a *call* —
/// `{ $0.name.lowercased() < $1.name.lowercased() }` — is not recognised, because the analyser cannot
/// see that the call is total and deterministic (`localizedCaseInsensitiveCompare` is the one this
/// rule was built for, and it is neither obviously). The residual it cannot see at all is a
/// floating-point key: `{ $0.score < $1.score }` on a `Double` is *not* a strict weak ordering once a
/// `NaN` is in the collection, and nothing in the syntax says whether `score` is a `Double`. Naming
/// the type is what would fix that, which is the rule's advice anyway.
enum FreeOrdering {

    static func describes(_ closure: ClosureExprSyntax) -> Bool {
        guard closure.statements.count == 1,
              let expression = ClosureBody.soleExpression(of: closure),
              let comparison = Comparison(expression),
              comparison.symbol == "<" || comparison.symbol == ">",
              let left = ClosureBody.memberPath(of: comparison.left),
              let right = ClosureBody.memberPath(of: comparison.right) else {
            return false
        }
        // Same key, different operands: `$0.date > $1.date`, not `$0.date > $0.cutoff`.
        return left.path == right.path && left.base != right.base
    }
}

/// One binary comparison, however the tree happens to be shaped.
///
/// `Parser.parse` does **not** fold infix operators, so `$0.date > $1.date` arrives as a
/// three-element `SequenceExprSyntax` and not as an `InfixOperatorExprSyntax`. Matching only the
/// folded form is a guard that never fires — and it fails *open*, flagging the very closures it is
/// meant to stay quiet about. Both shapes are read, so the rule behaves the same whether or not an
/// `OperatorTable` has run over the tree.
///
/// Anything longer than one comparison — `$0.a > $1.a || $0.b < $1.b` is a five-element sequence — is
/// not a single comparison at all, and falls out of the arity check here. That is the point: a
/// compound condition is a *rule*, and a rule can be wrong.
struct Comparison {
    let left: ExprSyntax
    let symbol: String
    let right: ExprSyntax

    init?(_ expression: ExprSyntax) {
        if let folded = expression.as(InfixOperatorExprSyntax.self) {
            guard let binary = folded.operator.as(BinaryOperatorExprSyntax.self) else {
                return nil
            }
            self.left = folded.leftOperand
            self.symbol = binary.operator.text
            self.right = folded.rightOperand
            return
        }

        guard let sequence = expression.as(SequenceExprSyntax.self),
              sequence.elements.count == 3 else {
            return nil
        }

        let elements = Array(sequence.elements)
        guard let binary = elements[1].as(BinaryOperatorExprSyntax.self) else { return nil }

        self.left = elements[0]
        self.symbol = binary.operator.text
        self.right = elements[2]
    }
}

enum ClosureBody {

    /// The single expression a one-statement closure evaluates, whether or not it says `return`.
    static func soleExpression(of closure: ClosureExprSyntax) -> ExprSyntax? {
        switch closure.statements.first?.item {
        case .expr(let expression):
            return expression

        case .stmt(let statement):
            return statement.as(ReturnStmtSyntax.self)?.expression

        default:
            return nil
        }
    }

    /// Splits `$0.file.name` into its base (`$0`) and its member path (`file.name`).
    ///
    /// A **call** anywhere in the chain returns `nil`, and that is what both callers lean on: plain
    /// stored access is the only thing either of them will call free. A call could be anything —
    /// locale-dependent, partial, or expensive — and the syntax does not say which.
    static func memberPath(of expression: ExprSyntax) -> (base: String, path: String)? {
        var path: [String] = []
        var current = expression

        while let member = current.as(MemberAccessExprSyntax.self) {
            path.append(member.declName.baseName.text)
            guard let base = member.base else { return nil }
            current = base
        }

        guard let reference = current.as(DeclReferenceExprSyntax.self) else { return nil }
        return (reference.baseName.text, path.reversed().joined(separator: "."))
    }
}

// The call-site vocabulary the closure rules share.
//
// **Two rules read this, which is why it is no longer private to one of them.** The census
// (`PureClosureCandidateVisitor`) reports the closures at these call sites that are pure; the
// inventory (`ImpureClosureVisitor`) reports the ones that are not. They must agree exactly on
// which closures are in scope, or the two numbers stop being complements and neither can be read
// against the other.
//
// This project has found the same shape four times over in the architecture rules — one rule
// privately holding the vocabulary its twin needs, and reporting something the twin already knew
// was not a finding. Lifting it before the second consumer is written is the cheap version of that
// fix.

/// A higher-order collection operation whose closure argument is a pure function by contract.
///
/// Deliberately a fixed list rather than "any call taking a closure". `Task { … }`,
/// `withAnimation { … }` and `DispatchQueue.main.async { … }` also take closures, and a closure run
/// for its effects is not a property waiting to be named. These are the operations whose closures
/// are *supposed* to be functions.
struct CollectionOperation {

    /// What the closure *is*, which is what decides whether naming it buys anything.
    enum Kind: Equatable {
        case comparator
        case predicate
        case transform
        case reducer

        /// The manifest's vocabulary for this classification.
        ///
        /// The rule has always known which of these a closure is — it picks the law sentence off
        /// exactly this distinction. Until the manifest grew a `role` field, that knowledge reached
        /// the reader as prose and reached the downstream tool not at all, so every finding here
        /// arrived as an undifferentiated "extractable-kernel at line N".
        var seedRole: PBTSeedRole {
            switch self {
            case .comparator:
                return .comparator

            case .predicate:
                return .predicate

            case .transform:
                return .transform

            case .reducer:
                return .reducer
            }
        }
    }

    let name: String

    /// The law worth stating once the closure has a name — the reason to bother extracting it.
    let law: String

    let kind: Kind

    init?(call: FunctionCallExprSyntax) {
        guard let callee = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }

        switch callee.declName.baseName.text {
        case "sorted", "sort", "min", "max", "partition":
            self.name = callee.declName.baseName.text
            self.law = "A comparator must be a strict weak ordering: irreflexive, antisymmetric and "
                + "transitive. Sorting with one that is not can crash, and no example test will "
                + "tell you which triple broke it."
            self.kind = .comparator

        case "filter", "first", "contains", "allSatisfy", "drop", "prefix", "removeAll":
            self.name = callee.declName.baseName.text
            self.law = "A predicate is a total function of its inputs — generate them and state "
                + "what it must accept and reject."
            self.kind = .predicate

        case "map", "compactMap", "flatMap":
            self.name = callee.declName.baseName.text
            self.law = "A transform is a function of its input — generate inputs and state what "
                + "the result must satisfy."
            self.kind = .transform

        case "reduce":
            self.name = "reduce"
            self.law = "A reducer's combine step is usually associative, and often has an identity "
                + "— both are laws a property test can check and an example cannot."
            self.kind = .reducer

        default:
            return nil
        }
    }

    /// Whether the closure hides a law that naming it would let you *state*.
    ///
    /// **Body size is the wrong axis, wherever the closure can be wrong on one line.** The comparators
    /// proved it: `{ $0.name <= $1.name }` is reflexive and `{ $0.a > $1.a || $0.b < $1.b }` is
    /// intransitive, each fits inside any floor, and each can crash `sorted(by:)`. Predicates have
    /// exactly the same shape — `{ $0.path.hasPrefix(parent) && $0.path != parent }` is one line and
    /// one off-by-one from wrong — so both ask the same question, in their own terms:
    ///
    /// - a **comparator** is free when its ordering is inherited whole from `Comparable`
    ///   (`{ $0.date > $1.date }`) — see `FreeOrdering`;
    /// - a **predicate** is free when it makes no decision at all and merely surfaces a stored `Bool`
    ///   (`{ $0.isEnabled }`) — see `FreeDecision`.
    ///
    /// Neither can be got wrong, so neither has a law left to state, and firing on them is the noise
    /// that teaches people to switch the category off. Everything else earns the finding.
    ///
    /// Transforms and reducers keep the size floor, and legitimately: a one-statement `map { $0.name }`
    /// is a *projection*, and unlike a predicate or a comparator it carries no law that a single
    /// expression could violate — there is nothing for it to be inconsistent with.
    func hidesALawWorthStating(_ closure: ClosureExprSyntax) -> Bool {
        switch kind {
        case .comparator:
            return !FreeOrdering.describes(closure)

        case .predicate:
            return !FreeDecision.describes(closure)

        case .transform, .reducer:
            return closure.statements.count >= 2
        }
    }
}

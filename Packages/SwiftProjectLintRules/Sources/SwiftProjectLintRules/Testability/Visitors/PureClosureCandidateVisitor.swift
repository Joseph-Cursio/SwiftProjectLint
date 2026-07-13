import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// The property test hiding inside a closure.
///
/// **An inline closure cannot be tested** — not *is hard to test*, cannot. There is no name to call
/// and no seam to reach it through. The only way to run it is to run the whole method containing it,
/// with all that method's state stood up around it, and then to infer what the closure did from what
/// the method returned. You are testing a predicate through a keyhole: the failure says the output
/// was wrong, not which input broke which closure.
///
/// It gets worse the more the closure is worth testing, because the closures that earn a test — a
/// branch, an ordering, an edge case — are the ones buried inside the methods with the most state
/// around them. The code most in need of a test is the code least reachable by one. That is true of
/// *any* test, not just a property test.
///
/// What makes it worth a rule is that it is self-inflicted and reversible: the closure is **pure**, a
/// function in everything but syntax. Nothing about it needs to be unreachable. The only thing
/// standing between it and a test is that nobody gave it a name.
///
/// The motivating case, and the reason this rule exists at all:
///
///     let immediateChildren = allFiles.filter { file in
///         let relativePath = file.path.replacingOccurrences(of: currentPath, with: "")
///         return relativePath.split(separator: "/").count <= 1
///     }
///     files = immediateChildren.sorted { file1, file2 in
///         if file1.isFolder != file2.isFolder { return file1.isFolder }
///         return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
///     }
///
/// Two pure functions with no names. The first contains a real bug — `replacingOccurrences` strips
/// *every* match, not just the leading one, so a grandchild is listed as a child — and it went
/// unnoticed because there was nothing to write a test against. Name it and the property writes
/// itself.
///
/// **A capture is not an impurity.** That predicate captures `currentPath`, which is a `var`.
/// Irrelevant: lift the body into `isImmediateChild(_ path: String, of parent: String)` and the
/// capture *becomes a parameter*. Refusing captured state would refuse the best finding this rule
/// has. What no extraction rescues is a closure that **writes** to what it captured — that one is
/// refuted, by the shared purity oracle.
///
/// `info` severity; opt-in. Reports a refactor, not a defect.
final class PureClosureCandidateVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false
    private let purityInferrer = PurityInferrer()

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture,
              let operation = CollectionOperation(call: node),
              let closure = node.trailingClosure ?? firstClosureArgument(of: node),
              operation.hidesALawWorthStating(closure),
              purityInferrer.isPure(closure) else {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: "The closure passed to `\(operation.name)` is pure — a property-based-test "
                + "candidate with no name to test. \(operation.law)",
            filePath: getFilePath(for: Syntax(closure)),
            lineNumber: getLineNumber(for: Syntax(closure)),
            suggestion: "Lift it into a named function. Anything it captures becomes a parameter, "
                + "and what is left is a pure function you can generate inputs for.",
            ruleName: .pureClosureCandidate,
            symbol: operation.name
        )
        return .visitChildren
    }

    /// The first closure passed as an ordinary (non-trailing) argument — `sorted(by: { … })`.
    private func firstClosureArgument(of call: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        call.arguments.lazy
            .compactMap { $0.expression.as(ClosureExprSyntax.self) }
            .first
    }
}

/// A higher-order collection operation whose closure argument is a pure function by contract.
///
/// Deliberately a fixed list rather than "any call taking a closure". `Task { … }`,
/// `withAnimation { … }` and `DispatchQueue.main.async { … }` also take closures, and a closure run
/// for its effects is not a property waiting to be named. These are the operations whose closures
/// are *supposed* to be functions.
private struct CollectionOperation {

    /// What the closure *is*, which is what decides whether naming it buys anything.
    enum Kind {
        case comparator
        case predicate
        case transform
        case reducer
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
private enum FreeDecision {

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
    private static func isPlainEquality(_ expression: ExprSyntax) -> Bool {
        guard let comparison = Comparison(expression),
              comparison.symbol == "==" || comparison.symbol == "!=" else {
            return false
        }
        return isPlainOperand(comparison.left) && isPlainOperand(comparison.right)
    }

    /// A stored path (`$0.status`), an implicit member (`.uploading`), or a literal. Anything else —
    /// a call above all — is doing work, and work can be wrong.
    private static func isPlainOperand(_ expression: ExprSyntax) -> Bool {
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
    private static func withoutNegation(_ expression: ExprSyntax) -> ExprSyntax {
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
private enum FreeOrdering {

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
private struct Comparison {
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

/// The two syntactic questions both freeness checks need to ask.
private enum ClosureBody {

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

import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// The property test hiding inside a closure.
///
/// `pureFunctionCandidate` can only point at a *declaration*. A great deal of the pure logic in
/// real Swift has none: a `filter` predicate or a `sorted(by:)` comparator written inline is a pure
/// function in everything but syntax, and being anonymous is the only thing standing between it and
/// a property test. The linter had nothing to say about them, so neither did the reader.
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
              closure.statements.count >= operation.minimumStatements,
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
    let name: String

    /// The law worth stating once the closure has a name — the reason to bother extracting it.
    let law: String

    /// A one-statement `map { $0.name }` is a projection, not a property; naming it buys nothing.
    let minimumStatements: Int

    /// Comparators are size-floored differently from the rest — see `hidesALawWorthStating`.
    private let isComparator: Bool

    init?(call: FunctionCallExprSyntax) {
        guard let callee = call.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }

        switch callee.declName.baseName.text {
        case "sorted", "sort", "min", "max", "partition":
            self.name = callee.declName.baseName.text
            self.law = "A comparator must be a strict weak ordering: irreflexive, antisymmetric and "
                + "transitive. Sorting with one that is not can crash, and no example test will "
                + "tell you which triple broke it."
            self.minimumStatements = 1
            self.isComparator = true

        case "filter", "first", "contains", "allSatisfy", "drop", "prefix", "removeAll":
            self.name = callee.declName.baseName.text
            self.law = "A predicate is a total function of its inputs — generate them and state "
                + "what it must accept and reject."
            self.minimumStatements = 2
            self.isComparator = false

        case "map", "compactMap", "flatMap":
            self.name = callee.declName.baseName.text
            self.law = "A transform is a function of its input — generate inputs and state what "
                + "the result must satisfy."
            self.minimumStatements = 2
            self.isComparator = false

        case "reduce":
            self.name = "reduce"
            self.law = "A reducer's combine step is usually associative, and often has an identity "
                + "— both are laws a property test can check and an example cannot."
            self.minimumStatements = 2
            self.isComparator = false

        default:
            return nil
        }
    }

    /// Whether the closure hides a law that naming it would let you *state*.
    ///
    /// Every operation but the comparators is floored on body size, and that is the whole test. A
    /// comparator cannot be, because the shortest comparators are the wrong ones: `{ $0.a > $1.a ||
    /// $0.b < $1.b }` and `{ $0.name <= $1.name }` each fit on one line and neither is a strict weak
    /// ordering — the second is not even irreflexive, and both can crash `sorted(by:)`.
    ///
    /// So the discriminator is not *size*, it is whether the ordering is **free**. A body that is one
    /// strict comparison of the same key on both sides — `{ $0.date > $1.date }` — inherits its
    /// ordering from the key's `Comparable` conformance and cannot be got wrong. There is no law left
    /// to state, and firing on it is the noise that teaches people to switch the category off.
    /// Everything else earns the finding: a branch, a `||`, a second key, a `compare(_:)` call.
    func hidesALawWorthStating(_ closure: ClosureExprSyntax) -> Bool {
        guard isComparator else { return true }
        return !FreeOrdering.describes(closure)
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
              let expression = soleExpression(of: closure),
              let comparison = Comparison(expression),
              comparison.symbol == "<" || comparison.symbol == ">",
              let left = key(of: comparison.left),
              let right = key(of: comparison.right) else {
            return false
        }
        // Same key, different operands: `$0.date > $1.date`, not `$0.date > $0.cutoff`.
        return left.path == right.path && left.base != right.base
    }

    /// One binary comparison, however the tree happens to be shaped.
    ///
    /// `Parser.parse` does **not** fold infix operators, so `$0.date > $1.date` arrives as a
    /// three-element `SequenceExprSyntax` and not as an `InfixOperatorExprSyntax`. Matching only the
    /// folded form is a guard that never fires — and it fails *open*, flagging the very comparators
    /// this is meant to stay quiet about. Both shapes are read, so the rule behaves the same whether
    /// or not an `OperatorTable` has run over the tree.
    ///
    /// Anything longer than one comparison — `$0.a > $1.a || $0.b < $1.b` is a five-element sequence
    /// — is not a free ordering, and falls out of the arity check here.
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

    /// The single expression a one-statement closure evaluates, whether or not it says `return`.
    private static func soleExpression(of closure: ClosureExprSyntax) -> ExprSyntax? {
        switch closure.statements.first?.item {
        case .expr(let expression):
            return expression

        case .stmt(let statement):
            return statement.as(ReturnStmtSyntax.self)?.expression

        default:
            return nil
        }
    }

    /// Splits `$0.file.name` into its base (`$0`) and its member path (`file.name`). A call anywhere
    /// in the chain returns `nil` — the ordering is only free when the key is plain stored access.
    private static func key(of expression: ExprSyntax) -> (base: String, path: String)? {
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

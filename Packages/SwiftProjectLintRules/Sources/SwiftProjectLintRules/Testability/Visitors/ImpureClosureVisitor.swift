import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// **The complement of the census: what is standing between you and a property test.**
///
/// `pureClosureCandidate` walks every closure at a higher-order call site, asks the purity oracle,
/// and reports the ones that pass. The ones that fail are dropped without a word. So the number this
/// tool publishes — closures worth naming — is an inventory of what is *already testable in
/// principle*, and the complement is computed on every run and thrown away.
///
/// For a reader whose goal is adopting property-based testing, the complement is the half they act
/// on. A pure closure needs a name. An **impure** one is the thing in the way, and until this rule
/// existed nothing counted them. SwiftProjectLint#186.
///
/// ## The same population, deliberately
///
/// This runs the *identical* gate — `CollectionOperation`, `hidesALawWorthStating`, the forwarding
/// check, the test-file exclusion — and differs in one clause: where the census requires
/// `refutation == nil`, this requires it to be present. That is what makes the two numbers
/// complements rather than two unrelated counts, and it is why the vocabulary those gates are
/// written in now lives in `CollectionOperation` rather than privately inside the census.
///
/// A test pins the partition directly: over the same source, no closure is reported by both rules,
/// and their sum is the population the shared gate admits.
///
/// ## It reports a fact, not a defect
///
/// An impure closure is ordinary Swift. `forEach { save($0) }` is correct, and
/// `sorted { $0.date < $1.date }` reading a stored date is correct. The finding is not *this is
/// wrong*; it is *here is where the effects are, and here is what to separate if you want a kernel*
/// — the same argument `extractableTotalKernel` makes one case at a time, made as a census.
///
/// **So this is deliberately not a seed.** It passes no `role`, and nothing downstream should point
/// analysis at it. `CandidateInventory` and `PBTSeedsFormatter` list the rules that *are* seeds, and
/// this is not among them.
///
/// ## What each cause is worth, which is why the message leads with it
///
/// `Impurity.Cause` groups the oracle's eleven refuters into five, on the test of whether a reader
/// does something different about them. The advice differs per cause and the message says so:
/// `.partiality` is the one most likely to be a latent bug, `.capturedWrite` is the one where the
/// honest advice is *nothing — the write is the closure's job*, and `.nondeterminism` usually has a
/// twin finding from `nonInjectedNondeterminism` pointing at the same line.
///
/// ## What it found, which is less than the issue assumed
///
/// Over 26 repositories: **31 impure closures against 875 pure ones — 3%** — 17 side effects, 8
/// captured writes, 4 traps, 2 nondeterministic reads.
///
/// The reason it is small is a fact about the design rather than the corpus: `CollectionOperation`
/// is a fixed list chosen because *"a closure run for its effects is not a property waiting to be
/// named"*, so `forEach`, `Task { }` and `withAnimation { }` were never in scope, and the size floor
/// drops single-expression transforms. **This counts the impure closures among the ones that were
/// supposed to be functions** — the population where an impurity is surprising — and not every
/// impure closure in a codebase. The doc page says so under the same heading, because the number
/// misleads badly if that clause is dropped.
///
/// `info` severity; opt-in. A census, like the two it sits beside.
final class ImpureClosureVisitor: BasePatternVisitor {

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
              !ForwardingCall.describes(closure, declaredInProject: knownProjectFunctions),
              let impurity = Impurity(purityInferrer.refutation(for: closure)) else {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: "The closure passed to `\(operation.name)` \(Self.finding(impurity)) — "
                + "not a property-test candidate until that is separated out.",
            filePath: getFilePath(for: Syntax(closure)),
            lineNumber: getLineNumber(for: Syntax(closure)),
            suggestion: Self.advice(for: impurity.cause),
            ruleName: .impureClosureInventory,
            symbol: EnclosingDeclaration.name(of: node) ?? operation.name
        )
        return .visitChildren
    }

    /// The first closure passed as an ordinary (non-trailing) argument — `sorted(by: { … })`.
    ///
    /// Duplicated from the census on purpose rather than shared: it is three lines of syntax
    /// navigation with no vocabulary in it, and the thing that must not drift between the two rules
    /// is *which call sites count*, which is shared. Sharing this too would make the shared surface
    /// larger without making the partition safer.
    private func firstClosureArgument(of call: FunctionCallExprSyntax) -> ClosureExprSyntax? {
        call.arguments.lazy
            .compactMap { $0.expression.as(ClosureExprSyntax.self) }
            .first
    }

    /// The clause that names the construct — *"reads the clock: `Date()`"*.
    ///
    /// The witness is the point of the rule. *"You have 400 untestable closures"* is a number;
    /// *"this one reads the clock, that one writes a file"* is a work list, and the difference is
    /// whether the reason is in the sentence.
    private static func finding(_ impurity: Impurity) -> String {
        switch impurity.cause {
        case .sideEffect: return "performs an effect: `\(impurity.witness)`"
        case .nondeterminism: return "reads something the inputs do not determine: `\(impurity.witness)`"
        case .partiality: return "is partial — it can trap on \(impurity.witness)"
        case .capturedWrite: return "writes to the captured `\(impurity.witness)`"
        case .declaredEffect: return "declares `\(impurity.witness)`"
        case .opaque: return "is refuted for a reason this analysis cannot name"
        }
    }

    /// What to do about it, which is different for every cause — including the one where the answer
    /// is *nothing*.
    private static func advice(for cause: Impurity.Cause) -> String {
        switch cause {
        case .sideEffect:
            return "There is usually a decision buried in here that the effect is carrying. "
                + "Lift the decision into a pure function and leave the effect at the call site."

        case .nondeterminism:
            return "Inject the source — a clock, a `RandomNumberGenerator`, an ID provider — so the "
                + "closure becomes a function of its arguments. `Non-Injected Nondeterminism` "
                + "reports the same line from the other direction."

        case .partiality:
            return "Make it total: return an Optional, or handle the case that traps. A property "
                + "test over generated inputs would crash here rather than falsify a law, which is "
                + "the same reason this closure is hard to trust in production."

        case .capturedWrite:
            return "Nothing, most likely — the write is what the closure is for, and no signature "
                + "change rescues it. Listed as a boundary of the pure region, not as a defect."

        case .declaredEffect:
            return "An `async` or `throws` closure is a different kind of thing from a predicate or "
                + "a transform. If the effect is incidental, the pure part can usually be split out."

        case .opaque:
            return "The oracle refuted this without naming a construct. Worth reading by hand."
        }
    }
}

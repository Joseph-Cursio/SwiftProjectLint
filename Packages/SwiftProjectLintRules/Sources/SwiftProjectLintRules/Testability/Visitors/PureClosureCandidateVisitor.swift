import Foundation
import SwiftProjectLintModels
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
              !ForwardingCall.describes(closure, declaredInProject: knownProjectFunctions),
              purityInferrer.isPure(closure) else {
            return .visitChildren
        }

        // A comparator whose keys this can read gets a name in the suggestion.
        // Silent for every other shape — see `ComparatorName` for why a name a
        // reader has to check is worse than no name at all.
        let suggestedName = operation.kind == .comparator
            ? ComparatorName.derived(from: closure)
            : nil
        let suggestion = suggestedName.map {
            "Lift it into `static func \($0)(_ lhs: …, _ rhs: …) -> Bool` and pass it by name. "
                + "The name states the whole ordering, including the tiebreak the closure body "
                + "makes you read four lines to find."
        } ?? "Lift it into a named function. Anything it captures becomes a parameter, "
            + "and what is left is a pure function you can generate inputs for."

        addIssue(
            severity: .info,
            message: "The closure passed to `\(operation.name)` is pure — a property-based-test "
                + "candidate with no name to test. \(operation.law)",
            filePath: getFilePath(for: Syntax(closure)),
            lineNumber: getLineNumber(for: Syntax(closure)),
            suggestion: suggestion,
            ruleName: .pureClosureCandidate,
            symbol: EnclosingDeclaration.name(of: node) ?? operation.name,
            role: operation.kind.seedRole
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

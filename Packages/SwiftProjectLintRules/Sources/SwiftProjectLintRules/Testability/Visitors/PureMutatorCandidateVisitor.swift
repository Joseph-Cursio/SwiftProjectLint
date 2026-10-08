import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Surfaces **pure mutators** — functions that return nothing and change exactly one value, as a
/// function of their inputs — as property-test candidates.
///
/// `pureFunctionCandidate` needs a result to assert on, so it refuses every mutator, and the seed
/// manifest never named one. SwiftLintRuleStudio's `MigrationAssistant.applyMigration(_:to:)` is
/// the case on record: it writes a config through `inout`, owes idempotence (a migration applied
/// twice changes nothing the first application did not), and was invisible to the pipeline. A
/// mutator has a result all the same — the value it leaves behind — so a test copies the value,
/// applies the mutator, and compares.
///
/// Two shapes, both judged by `PropertyTestCandidacy.mutatorCandidate(of:…)`: a function with one
/// `inout` parameter, and a `mutating` method of a value type. The mutated value must already be
/// comparable; one a bare `: Equatable` would fix is reported by `missingEquatableOnPureResult`
/// instead, so the two never name the same declaration.
///
/// A census, like the other candidate rules — see `CandidateInventory`. Each finding seeds the
/// manifest as a `pure-mutator` naming what it `mutates`.
final class PureMutatorCandidateVisitor: BasePatternVisitor, PackagePurityConsumer {

    /// The oracle through `mutatorCandidate`, the clean-method catalog its call-shape check reads,
    /// and the one-hop join — the same three inputs as `pureFunctionCandidate`.
    static let packagePurityInputs: PackagePurityInputs = [.oracle, .cleanInstanceMethods, .impurePackageFunctions]

    private var fileIsTestOrFixture = false

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture,
              let mutator = PropertyTestCandidacy.mutatorCandidate(
                  of: node,
                  knownEquatableTypes: knownEquatableTypes,
                  knownValueTypes: knownValueTypes,
                  cleanInstanceMethods: knownCleanInstanceMethods
              ),
              mutator.equatable.isEmpty,
              !Self.reachesImpureCallee(node, settled: knownImpurePackageFunctions.settledNames) else {
            return .visitChildren
        }

        let name = node.name.text
        let restriction = PropertyTestCandidacy.restriction(of: node)
        let claim = mutator.candidate.isPartial ? "looks pure but partial — it `throws`" : "looks pure and total"
        let what = mutator.mutates == "self"
            ? "a `mutating` method: it changes only `self`, as a function of `self` and its inputs"
            : "it changes only `\(mutator.mutates)`, as a function of its inputs"
        var advice = Self.lawAdvice(mutates: mutator.mutates)
        if restriction != nil { advice = PureFunctionCandidateVisitor.wideningAdvice }

        addIssue(
            severity: .info,
            message: "`\(name)(…)` \(claim) — a good property-based-test candidate (\(what))"
                + "\(restriction == nil ? "" : PureFunctionCandidateVisitor.unreachableClause)",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: advice,
            ruleName: .pureMutatorCandidate,
            symbol: name,
            testReachability: restriction.map(TestReachability.unreachable) ?? .reachable,
            mutates: mutator.mutates
        )
        return .visitChildren
    }

    /// How to state a law over something that returns nothing.
    static func lawAdvice(mutates: String) -> String {
        let value = mutates == "self" ? "the value" : "`\(mutates)`"
        return "A mutator returns nothing, so state the law over what it leaves behind: copy "
            + "\(value), apply it, and compare — a second application for idempotence, an "
            + "independent copy given the same inputs for determinism. `swift-infer discover` "
            + "reads the seed's `mutates` to write the `&` call."
    }

    /// The one-hop join `pureFunctionCandidate` applies: a body reaching a package function the
    /// oracle refutes is not pure, whatever the declaration alone says.
    static func reachesImpureCallee(_ node: FunctionDeclSyntax, settled: Set<String>) -> Bool {
        guard let body = node.body, !settled.isEmpty else { return false }
        return PackagePurityJoin.impureCallee(in: Syntax(body), settledImpureNames: settled) != nil
    }
}

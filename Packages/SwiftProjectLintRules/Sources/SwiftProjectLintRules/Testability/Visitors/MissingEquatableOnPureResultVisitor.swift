import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Flags a pure function that is kept out of property testing **only** because its result is not
/// `Equatable` — and the conformance would be synthesized.
///
/// `pureFunctionCandidate` refuses such a function, rightly: a law has to compare its result. But
/// it refuses silently, so a function one keyword away from a property test looks exactly like one
/// that has nothing to offer. SwiftLintRuleStudio's `MigrationAssistant.detectMigrations` is the
/// case on record: pure and total, returning a `MigrationPlan` of strings and `MigrationStep`s that
/// nobody had declared `Equatable` — absent from the seed manifest, while a mutation run left eight
/// mutants alive in the same file.
///
/// The sibling of `missingEquatableOnStateType`, and narrower by design. A blanket "this struct
/// could be `Equatable`" would fire on most value types in a project, and a conformance nobody
/// compares is API surface with no return. What earns this finding is that a pure function is
/// **waiting** on it, so it is raised at the function and names the types to change.
///
/// It **diagnoses** rather than nominates — there is a specific edit to make — which is why it is
/// not one of `CandidateInventory`'s collapsed census rules.
///
/// The finding also seeds the manifest as a `pure-function` carrying `requires`, so `swift-infer`
/// can name the conformance in the stub it writes rather than proposing a law that does not
/// compile. See `PBTSeedRequirement`.
final class MissingEquatableOnPureResultVisitor: BasePatternVisitor, PackagePurityConsumer {

    /// The oracle through `PropertyTestCandidacy.equatableNearMiss`, the clean-method catalog it is
    /// handed, and the one-hop join — the same inputs as `pureFunctionCandidate`, because it asks
    /// the same question with one gate moved.
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
              let nearMiss = PropertyTestCandidacy.equatableNearMiss(
                  of: node,
                  knownEquatableTypes: knownEquatableTypes,
                  equatableRemedies: knownEquatableRemedies,
                  knownValueTypes: knownValueTypes,
                  cleanInstanceMethods: knownCleanInstanceMethods
              ) else {
            return .visitChildren
        }

        // The same one-hop join `pureFunctionCandidate` applies: a body reaching a package function
        // the oracle refutes is not pure, whatever the declaration alone says.
        let settled = knownImpurePackageFunctions.settledNames
        if let body = node.body, !settled.isEmpty,
           PackagePurityJoin.impureCallee(in: Syntax(body), settledImpureNames: settled) != nil {
            return .visitChildren
        }

        let name = node.name.text
        let types = nearMiss.equatable
        let restriction = PropertyTestCandidacy.restriction(of: node)
        let claim = nearMiss.candidate.isPartial ? "looks pure but partial" : "looks pure and total"
        var suggestion = "Add `Equatable` to \(Self.list(types)). Every stored property and "
            + "associated value \(types.count == 1 ? "it holds" : "they hold") is already `Equatable`"
            + "\(types.count == 1 ? "" : " or on this list"), so the compiler synthesizes the "
            + "conformance, and `\(name)(…)` becomes a property-test candidate."
        if restriction != nil {
            suggestion += " " + PureFunctionCandidateVisitor.wideningAdvice
        }

        addIssue(
            severity: .info,
            message: "`\(name)(…)` \(claim), but no property test can compare its result: "
                + "`\(types[0])` is not `Equatable`"
                + "\(restriction == nil ? "" : PureFunctionCandidateVisitor.unreachableClause)",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: suggestion,
            ruleName: .missingEquatableOnPureResult,
            symbol: name,
            role: DeclaredRoleClassifier.role(of: node, isPartial: nearMiss.candidate.isPartial),
            testReachability: restriction.map(TestReachability.unreachable) ?? .reachable,
            requires: PBTSeedRequirement(equatable: types)
        )
        return .visitChildren
    }

    /// `A`, `A` and `B`, or `A`, `B` and `C` — each in backticks.
    private static func list(_ names: [String]) -> String {
        let quoted = names.map { "`\($0)`" }
        guard let last = quoted.last, quoted.count > 1 else { return quoted.first ?? "" }
        return quoted.dropLast().joined(separator: ", ") + " and " + last
    }
}

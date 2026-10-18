import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// What the rules that read the package purity may report on: no file the construction universe
/// leaves out, because the facts were built without the types that file declares.
extension ProjectLinter {

    /// `issues` without the findings of a rule that reads the package purity on a file the run
    /// could not judge with its own types.
    ///
    /// **Why.** The facts hold the types of the universe's production sources
    /// (`ConstructionUniverse.isProductionSource`), and a reported file is not always one of them.
    /// A test suite's folder — `test/`, `tests/`, `validation-test/` — is out of the universe (the
    /// shared spec's amendment W) yet reported as production, since reporting's test-file
    /// classifier (`BasePatternVisitor.isTestOrFixturePath`) shares only the test-target clause; a
    /// manifest is out too. Such a file was judged without the types it declares itself, and the
    /// oracle judges constructing a type it does not know as pure — the unsound direction.
    /// `struct Probe` printing in its `init`, beside `func probeValue(_ n: Int) -> Int { Probe(n: n).n }`
    /// in `tests/Support/`, made `probeValue` a Pure Function Property-Test Candidate, and a `map`
    /// closure building a `Probe` a Pure Closure one, missing from Impure Closure Inventory. Under
    /// `prod/Support/`, neither was a candidate.
    ///
    /// Putting the suites back into the universe is not the answer: the swift compiler's 22,600 test
    /// programs are why they left, and the rule is shared word for word with SwiftInferProperties.
    /// So the readers stop short of what they cannot judge, and every other rule reports on those
    /// files as before. `Tests/` and `*Tests/` folders change nothing here: they are out of the
    /// universe *and* test files to reporting, which every reader already skips.
    ///
    /// **Which rules.** Those whose visitor declares a purity input (`PackagePurityConsumer`) — the
    /// declaration the purity gate is derived from, which `PurityGateDeclarationTests` makes every
    /// reader carry, so a new reader is covered without a list to keep. The declaration decides, not
    /// how a finding leans on the purity: Could Be Private reads it only for a caveat in its message,
    /// and Direct Instantiation for an exemption, and both would still phrase or exempt by an
    /// unsound verdict. The whole file is dropped for a reader, including a finding that no unknown
    /// construction moved, since nothing short of the facts says which those are.
    ///
    /// **Which files.** Classified where the walk reached them (`universePath(for:projectRoot:)`),
    /// as the universe classifies them, and matched as findings name them
    /// (`relativePath(for:projectRoot:)`, links resolved). A file is out only when every path the run
    /// reached it by is: a production link to a file under `tests/` puts that file's types in the
    /// facts, at the link, so it is judged. A file with no universe path at all — not under the root —
    /// is left as it was.
    static func withinPurityScope(
        _ issues: [LintIssue],
        reportable: [String],
        projectRoot: String,
        registry: PatternVisitorRegistry
    ) -> [LintIssue] {
        let readers = Set(registry.getAllPatterns().filter { !$0.packagePurityInputs.isEmpty }.map(\.name))
        let named = Set(issues.filter { readers.contains($0.ruleName) }.map(\.filePath))
        // A run with no reader finding — every narrow run of other rules — classifies nothing.
        guard !named.isEmpty else { return issues }
        let unjudged = filesOutsideTheUniverse(reportable, projectRoot: projectRoot, among: named)
        guard !unjudged.isEmpty else { return issues }
        return issues.filter { !readers.contains($0.ruleName) || !unjudged.contains($0.filePath) }
    }

    /// Which of `named` — files as findings name them — are reported files that no path the run
    /// reached them by puts among the construction universe's production sources.
    ///
    /// Resolving every production path, to see whether one is a link to a left-out file, is the one
    /// costly step, so it is taken only when a left-out file is named at all. A default run on a
    /// package always has one left out, its manifest, and seldom a finding on it.
    static func filesOutsideTheUniverse(
        _ reportable: [String],
        projectRoot: String,
        among named: Set<String>
    ) -> Set<String> {
        var production: [String] = []
        var outside: Set<String> = []
        for filePath in reportable {
            guard let universePath = universePath(for: filePath, projectRoot: projectRoot) else { continue }
            if ConstructionUniverse.isProductionSource(relativePath: universePath) {
                production.append(filePath)
            } else {
                outside.insert(relativePath(for: filePath, projectRoot: projectRoot))
            }
        }
        outside.formIntersection(named)
        guard !outside.isEmpty else { return [] }
        return outside.subtracting(production.map { relativePath(for: $0, projectRoot: projectRoot) })
    }
}

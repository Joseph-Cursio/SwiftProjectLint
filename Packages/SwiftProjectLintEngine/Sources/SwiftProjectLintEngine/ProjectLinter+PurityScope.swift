import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// What the rules that read the package purity may report on: only a file the facts were built
/// from, because of any other the facts do not know the types it declares.
extension ProjectLinter {

    /// `issues` without the findings of a rule that reads the package purity on a file the run
    /// could not judge with its own types.
    ///
    /// **Why.** The facts hold the types of the universe's production sources
    /// (`ConstructionUniverse.isProductionSource`), and a reported file is not always one of them.
    /// A test suite's folder — `test/`, `tests/`, `validation-test/` — is out of the universe (the
    /// shared spec's amendment W) yet reported as production, since reporting's test-file
    /// classifier (`BasePatternVisitor.isTestOrFixturePath`) shares only the test-target clause; a
    /// manifest is out too, and so is a file that is not strict UTF-8 (amendment C), which the
    /// lenient read still reports on. Such a file was judged without the types it declares itself,
    /// and the oracle judges constructing a type it does not know as pure — the unsound direction.
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
    /// construction moved, since nothing short of the facts says which those are. So the
    /// declaration now decides where a reader reports too: one that forgets it still costs only a
    /// second pass in what is built, but reports on these files as if it read nothing.
    ///
    /// **Which files.** The run's own answer, not a second classification: `judgedFiles`, the files
    /// on disk whose trees the facts were built from, links resolved (`constructionSources`), matched
    /// against the file a finding names (`relativePath(for:projectRoot:)`, which resolves links the
    /// same way). Every path the universe reached a file by counts, reported or not, so a production
    /// link to a file under `tests/` keeps that file judged even when `excluded_paths` hides the
    /// link or it sits in a nested package the root compiles but the run does not report on. A run
    /// that resolved no universe (`judgedFiles` `nil`) is left as it was: its purity was withheld,
    /// and a reader that read it tripped the pass, whose findings are discarded, so a reader
    /// finding that stands read none of it.
    static func withinPurityScope(
        _ issues: [LintIssue],
        judgedFiles: Set<String>?,
        projectRoot: String,
        registry: PatternVisitorRegistry
    ) -> [LintIssue] {
        guard let judgedFiles else { return issues }
        let readers = Set(registry.getAllPatterns().filter { !$0.packagePurityInputs.isEmpty }.map(\.name))
        let named = Set(issues.filter { readers.contains($0.ruleName) }.map(\.filePath))
        // A run with no reader finding — every narrow run of other rules — matches nothing.
        guard !named.isEmpty else { return issues }
        let unjudged = unjudgedFiles(among: named, judgedFiles: judgedFiles, projectRoot: projectRoot)
        guard !unjudged.isEmpty else { return issues }
        return issues.filter { !readers.contains($0.ruleName) || !unjudged.contains($0.filePath) }
    }

    /// Which of `named` — files as findings name them — are not among `judgedFiles`.
    ///
    /// A finding names its file as `relativePath(for:projectRoot:)` does: links resolved on both
    /// sides and the resolved root dropped, or the whole resolved path for a file outside the root.
    /// Undoing that takes one resolution, the root's; the facts' files were resolved already, by the
    /// shared parse that collapsed a link and its target into one entry.
    static func unjudgedFiles(among named: Set<String>, judgedFiles: Set<String>, projectRoot: String) -> Set<String> {
        let resolvedRoot = URL(fileURLWithPath: projectRoot).resolvingSymlinksInPath().path
        let prefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        return named.filter { name in
            !judgedFiles.contains(name.hasPrefix("/") ? name : prefix + name)
        }
    }
}

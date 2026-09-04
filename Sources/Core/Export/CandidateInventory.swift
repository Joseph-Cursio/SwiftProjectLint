import SwiftProjectLintModels

/// The rules that take a **census** rather than report a defect, and what to do about their volume.
///
/// On this repository a default run produces 876 findings, and **664 of them — 76% — are the two
/// property-test candidate rules**. That is not a bug in either rule: there really are 460 pure
/// functions and 204 pure closures, and the pipeline needs every one of them, because
/// `--format pbt-seeds` projects the same findings into the manifest `swift-infer` consumes.
///
/// It is a bug in what a human sees. The road test's sharpest result was that the linter **found**
/// a real defect in its own configuration code, **reported it correctly**, and the finding went
/// unread — buried among hundreds of "this function is pure" lines that require no action and
/// cannot be wrong. Volume that large does not inform; it functions as silence.
///
/// `PBT_TESTABILITY_RULES_SCOPE.md` predicted this before the rules were written. Decision 5 reads
/// *"Rule 5 opt-in (info, advisory)"*. It shipped default-on, and this is that decision arriving
/// late, in the only place it can arrive without breaking the pipeline.
///
/// ## Why presentation and not detection
///
/// Disabling the rules would be the obvious reading of "opt-in" and it is the wrong one. The CLI
/// computes `issues` **once** and hands the same array to the report formatter and to
/// `PBTSeedsFormatter`. Turn the rules off and the seed manifest empties — the linter stops feeding
/// `swift-infer` at all. The detection is correct and must keep running; only the enumeration is
/// wrong.
///
/// So the candidates are still found, still counted in the summary, still exported, and still
/// exit-code relevant. They are simply not printed one per line in a report a person reads.
///
/// ## Why these two rules and not the whole category
///
/// `.extractableTotalKernel` stays listed, and the distinction is what the rule *asks of the reader*
/// rather than how many there are. A candidate rule **nominates**: "this is pure, it could be
/// property-tested." There is nothing to do per item — you hand the manifest to a tool. The kernel
/// rule **diagnoses**: "pure logic is trapped in an impure method, and here is the refactor." That
/// is a claim about a specific place, it can be wrong, and it is worth reading each time.
///
/// The other `.testability` rules — global mutable state, non-injected nondeterminism — are
/// warnings about things that are broken. They stay.
public enum CandidateInventory {

    /// Rules that nominate rather than diagnose.
    ///
    /// Deliberately **not** derived from `PBTSeedsFormatter.seedKinds`, even though it would catch
    /// three of these four. `.idempotencyViolation` seeds the pipeline too and is an *error* about
    /// a contract that is already broken; collapsing it would hide a defect. Seeding the pipeline
    /// and being a census are different properties, and only one of them is about volume.
    public static let inventoryRules: Set<RuleIdentifier> = [
        .pureFunctionCandidate,
        .pureClosureCandidate
    ]

    /// The report split into what a reader should see and what should be counted but not listed.
    public struct Split {
        /// Findings to print, one per line.
        public let listed: [LintIssue]

        /// Candidates withheld from the listing. Never dropped: the summary counts them and the
        /// notice names them.
        public let withheld: [LintIssue]

        public init(listed: [LintIssue], withheld: [LintIssue]) {
            self.listed = listed
            self.withheld = withheld
        }
    }

    /// Partition `issues`, or don't.
    ///
    /// - Parameter collapsing: `false` returns everything as `listed`, which is what an explicit
    ///   `--categories testability` must do. Asking for the category *is* the opt-in.
    public static func split(_ issues: [LintIssue], collapsing: Bool) -> Split {
        guard collapsing else { return Split(listed: issues, withheld: []) }
        return Split(
            listed: issues.filter { !inventoryRules.contains($0.ruleName) },
            withheld: issues.filter { inventoryRules.contains($0.ruleName) }
        )
    }

    /// A per-rule tally, in descending count order, for the notice.
    public static func tally(of withheld: [LintIssue]) -> [(rule: RuleIdentifier, count: Int)] {
        var counts: [RuleIdentifier: Int] = [:]
        for issue in withheld {
            counts[issue.ruleName, default: 0] += 1
        }
        return counts
            .map { (rule: $0.key, count: $0.value) }
            .sorted { ($0.count, $0.rule.rawValue) > ($1.count, $1.rule.rawValue) }
    }
}

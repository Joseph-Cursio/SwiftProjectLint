/// A stable reporting order for findings, so two runs over unchanged sources emit the same report.
///
/// Per-file analysis runs in a `TaskGroup` and collects results as they *complete*, which is a
/// different order on every run. The findings themselves were already stable — same files, same
/// lines, same rules — but roughly 83% of them landed in a different position run to run, which
/// makes the obvious regression check impossible: `diff old.txt new.txt` after a change reports
/// hundreds of spurious differences, so a reader cannot tell what their edit actually fixed.
///
/// Sorting is done once, at the end of analysis, rather than per formatter. Every output format
/// inherits the same order that way, and the ordering guarantee belongs to the analysis result
/// rather than to whichever renderer happens to be asked for it.
extension LintIssue {

    /// Whether `lhs` sorts before `rhs` in a report.
    ///
    /// Path and line come first, because a reader scanning one file wants its findings together and
    /// in source order. The components after them exist to make the order **total**: `sorted(by:)`
    /// is not guaranteed stable, so any two findings that compare equal may still swap places
    /// between runs. Comparing on everything the text report prints — rule, message, suggestion —
    /// means findings that tie are byte-identical in the output, so their relative order cannot be
    /// observed. `symbol` is the last resort for the machine-readable formats, which carry fields
    /// the text report does not.
    ///
    /// Written as a chain of comparisons rather than one tuple comparison because a tuple wide
    /// enough to hold all six components is both a `large_tuple` violation and the kind of
    /// expression that has timed out this project's type-checker on slower toolchains.
    public static func precedes(_ lhs: LintIssue, _ rhs: LintIssue) -> Bool {
        if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
        if lhs.lineNumber != rhs.lineNumber { return lhs.lineNumber < rhs.lineNumber }
        if lhs.ruleName != rhs.ruleName { return lhs.ruleName.rawValue < rhs.ruleName.rawValue }
        if lhs.message != rhs.message { return lhs.message < rhs.message }

        let leftSuggestion = lhs.suggestion ?? ""
        let rightSuggestion = rhs.suggestion ?? ""
        if leftSuggestion != rightSuggestion { return leftSuggestion < rightSuggestion }

        return (lhs.symbol ?? "") < (rhs.symbol ?? "")
    }
}

extension Array where Element == LintIssue {

    /// The findings in reporting order — see `LintIssue.precedes`.
    public func sortedForReporting() -> [LintIssue] {
        sorted(by: LintIssue.precedes)
    }
}

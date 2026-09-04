import Foundation

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
///
/// ## Why the comparator reads fields no reader sorts by
///
/// The order must be **total over everything any formatter renders**, not just over the components
/// a reader would think to sort by. `sorted(by:)` is not guaranteed stable, so two findings that
/// compare equal may swap places between runs — and if they render differently, that swap is a
/// spurious `diff` line, which is the whole problem this file exists to remove.
///
/// This was originally complete only for path, line, rule, message, suggestion and symbol, and the
/// doc comment claimed that covered "everything the text report prints". It did not: `TextFormatter`
/// renders `filepath:line: severity: [rule] message`, so **`severity` was printed and not
/// compared**. Three more fields had the same gap — the tail of `locations` (the comparator read
/// only `locations.first`, through `filePath`/`lineNumber`, while JSON and CSV render every
/// element), the `nil`-versus-`""` distinction the old `?? ""` collapsed (synthesized `Codable`
/// omits a `nil` key and emits `""` for an empty one), and the seed metadata that `pbt-seeds`
/// carries. See `ReportOrderDeterminismLawsTests`, which states the law and holds these four
/// witnesses.
///
/// **Stability is deliberately not the fix.** Decorating with the original index would make
/// `sorted` stable, and stability preserves *arrival* order — which is the `TaskGroup` completion
/// order, the nondeterminism being removed. A stable sort would pin the report to exactly the thing
/// that varies.
extension LintIssue {

    /// Whether `lhs` sorts before `rhs` in a report.
    ///
    /// Path and line come first, because a reader scanning one file wants its findings together and
    /// in source order. Everything after them is a tiebreak of last resort, present for totality
    /// rather than legibility — a reader never reaches them, because findings that get that far are
    /// identical in every component a reader reads.
    ///
    /// Written as a chain of `ComparisonResult` stages rather than one tuple comparison because a
    /// tuple wide enough to hold all the components is both a `large_tuple` violation and the kind
    /// of expression that has timed out this project's type-checker on slower toolchains. Split
    /// into three stages for the same reason, and because they answer to different readers: the
    /// text report, the machine-readable exports, and the `pbt-seeds` manifest.
    public static func precedes(_ lhs: LintIssue, _ rhs: LintIssue) -> Bool {
        readerFacingOrder(lhs, rhs)
            .then { exportedPayloadOrder(lhs, rhs) }
            .then { seedMetadataOrder(lhs, rhs) }
            == .orderedAscending
    }

    /// The components a human scanning the report actually reads, in the order they read them.
    ///
    /// `severity` sits here rather than among the tiebreaks because `TextFormatter` prints it on
    /// every line. It is compared on `rawValue` — an arbitrary but total order, which is all a
    /// tiebreak owes; ranking `error` above `warning` would be a *reporting* decision, and this
    /// stage only reaches severity once path, line, rule and message have all tied.
    private static func readerFacingOrder(_ lhs: LintIssue, _ rhs: LintIssue) -> ComparisonResult {
        order(lhs.filePath, rhs.filePath)
            .then { order(lhs.lineNumber, rhs.lineNumber) }
            .then { order(lhs.ruleName.rawValue, rhs.ruleName.rawValue) }
            .then { order(lhs.message, rhs.message) }
            .then { order(lhs.severity.rawValue, rhs.severity.rawValue) }
    }

    /// What the machine-readable formats carry beyond the text report: the full location list, and
    /// the two optionals whose emptiness is observable in JSON.
    private static func exportedPayloadOrder(_ lhs: LintIssue, _ rhs: LintIssue) -> ComparisonResult {
        order(lhs.suggestion, rhs.suggestion)
            .then { order(lhs.symbol, rhs.symbol) }
            .then { locationOrder(lhs.locations, rhs.locations) }
    }

    /// The `pbt-seeds` fields — what the manifest hands to `swift-infer`.
    ///
    /// `testReachability` is compared through `restriction` alone, and that is complete rather than
    /// partial: `.reachable` and `.unknown` both carry no restriction *and* `effectiveKind` treats
    /// them the same, so no formatter can distinguish them. Compare what is rendered.
    private static func seedMetadataOrder(_ lhs: LintIssue, _ rhs: LintIssue) -> ComparisonResult {
        order(lhs.role?.rawValue, rhs.role?.rawValue)
            .then {
                order(
                    lhs.testReachability.restriction?.rawValue,
                    rhs.testReachability.restriction?.rawValue
                )
            }
            .then { effectOrder(lhs.effect, rhs.effect) }
    }

    /// Lexicographic over the whole list, shorter first — so an issue's second and later locations
    /// are part of the order, not just the first one `filePath`/`lineNumber` expose.
    private static func locationOrder(
        _ lhs: [(filePath: String, lineNumber: Int)],
        _ rhs: [(filePath: String, lineNumber: Int)]
    ) -> ComparisonResult {
        for (left, right) in zip(lhs, rhs) {
            let element = order(left.filePath, right.filePath)
                .then { order(left.lineNumber, right.lineNumber) }
            if element != .orderedSame { return element }
        }
        return order(lhs.count, rhs.count)
    }

    /// Every field `PBTSeedEffect` encodes, because every one of them reaches the manifest.
    private static func effectOrder(_ lhs: PBTSeedEffect?, _ rhs: PBTSeedEffect?) -> ComparisonResult {
        guard let left = lhs else { return rhs == nil ? .orderedSame : .orderedAscending }
        guard let right = rhs else { return .orderedDescending }

        return order(left.declared.rawValue, right.declared.rawValue)
            .then { order(left.resolved.rawValue, right.resolved.rawValue) }
            .then { order(left.provenance.rawValue, right.provenance.rawValue) }
            .then { order(left.anchor?.rawValue, right.anchor?.rawValue) }
            .then { order(left.reason, right.reason) }
            .then { order(left.depth ?? -1, right.depth ?? -1) }
    }

    /// A total order over `String?` that keeps `nil` and `""` **distinct**.
    ///
    /// The old comparator coalesced both to `""`, which made them tie while synthesized `Codable`
    /// renders them differently — an omitted key against `"suggestion": ""`. `nil` sorts first,
    /// arbitrarily; what matters is only that the two are separable.
    private static func order(_ lhs: String?, _ rhs: String?) -> ComparisonResult {
        switch (lhs, rhs) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (left?, right?): return order(left, right)
        }
    }

    private static func order<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        if lhs < rhs { return .orderedAscending }
        if lhs > rhs { return .orderedDescending }
        return .orderedSame
    }
}

extension ComparisonResult {

    /// The next comparison in a lexicographic chain, evaluated only on a tie.
    ///
    /// Lets `precedes` read as the ordered list of components it is, rather than as a ladder of
    /// early returns — and keeps each stage returning a three-valued result, so "equal" never has
    /// to be spelled as an optional `Bool`.
    ///
    /// `internal` rather than `fileprivate` only to satisfy `strict_fileprivate`; it is an
    /// implementation detail of `LintIssue.precedes` and nothing else should reach for it.
    func then(_ next: () -> ComparisonResult) -> ComparisonResult {
        self == .orderedSame ? next() : self
    }
}

extension Array where Element == LintIssue {

    /// The findings in reporting order — see `LintIssue.precedes`.
    public func sortedForReporting() -> [LintIssue] {
        sorted(by: LintIssue.precedes)
    }
}

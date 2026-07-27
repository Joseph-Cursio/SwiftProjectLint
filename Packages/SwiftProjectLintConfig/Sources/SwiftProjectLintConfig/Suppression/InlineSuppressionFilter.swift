import Foundation
import SwiftProjectLintModels

/// Filters lint issues according to inline suppression comments in the source file.
///
/// Works per-file: callers supply issues *for a single file* plus that file's source
/// text. Per-file rules go through `analyzeFile`; cross-file rules are grouped by
/// their primary file (first `LintIssue.locations` entry) and filtered via
/// `ProjectLinter.applyInlineSuppression(to:files:)`.
///
/// Multi-location issues (a single diagnostic pointing at several files — rare for
/// idempotency rules, more common for duplicate-state rules) are filtered against
/// the primary file only. If you want suppression to respect every location, place a
/// `swiftprojectlint:disable`-shaped comment at the primary file's site.
public struct InlineSuppressionFilter {

    /// Returns `issues` with any suppressed violations removed.
    ///
    /// - Parameters:
    ///   - issues:      Issues detected for a single file.
    ///   - fileContent: The raw source text of that file.
    public static func filter(_ issues: [LintIssue], fileContent: String) -> [LintIssue] {
        guard !issues.isEmpty else { return issues }

        let directives = InlineSuppressionParser.parse(fileContent: fileContent)
        guard !directives.isEmpty else { return issues }

        let lines = fileContent.components(separatedBy: "\n")
        let ranges = buildSuppressedRanges(from: directives, lines: lines)

        return issues.filter { !isSuppressed(line: $0.lineNumber, rule: $0.ruleName, in: ranges) }
    }

    // MARK: - Private

    /// Maps a rule (nil = all rules) to the closed line ranges where it is suppressed.
    private typealias SuppressedRanges = [RuleIdentifier?: [(start: Int, end: Int)]]

    private static func buildSuppressedRanges(
        from directives: [SuppressionDirective],
        lines: [String]
    ) -> SuppressedRanges {
        let lineCount = lines.count
        var ranges: SuppressedRanges = [:]
        // Open disable regions: key → start line. nil key means "all rules".
        var openDisables: [RuleIdentifier?: Int] = [:]

        for directive in directives.sorted(by: { $0.line < $1.line }) {
            // An empty rules set targets all rules, represented by a nil dictionary key.
            let keys: [RuleIdentifier?] = directive.rules.isEmpty
                ? [nil]
                : directive.rules.map { Optional($0) }
            applyDirective(
                directive,
                keys: keys,
                lines: lines,
                ranges: &ranges,
                openDisables: &openDisables
            )
        }

        // Close any regions still open at end of file
        for (key, start) in openDisables {
            appendRange(to: &ranges, key: key, start: start, end: lineCount)
        }

        return ranges
    }

    private static func applyDirective(
        _ directive: SuppressionDirective,
        keys: [RuleIdentifier?],
        lines: [String],
        ranges: inout SuppressedRanges,
        openDisables: inout [RuleIdentifier?: Int]
    ) {
        switch directive.kind {
        case .disable:
            for key in keys where openDisables[key] == nil {
                openDisables[key] = directive.line
            }

        case .enable:
            closeDisableRegions(keys: keys, endLine: directive.line - 1, ranges: &ranges, openDisables: &openDisables)

        case .disableNext:
            let target = nextCodeLine(after: directive.line, in: lines)
            appendSingleLineRange(keys: keys, line: target, ranges: &ranges)

        case .disableThis:
            appendSingleLineRange(keys: keys, line: directive.line, ranges: &ranges)
        }
    }

    /// The first line after `line` that carries code — skipping blank lines and
    /// comments, including doc comments.
    ///
    /// `disable:next` used to mean literally `line + 1`, which silently missed
    /// any *documented* declaration: the directive landed on the doc comment and
    /// the declaration went unsuppressed. That is unfixable by reordering on a
    /// project that also runs SwiftLint, whose `orphaned_doc_comment` requires
    /// the opposite adjacency — a `///` block must touch its declaration. The
    /// two demands are unsatisfiable together, and reordering to satisfy
    /// SwiftLint disables every `disable:next` in the file without any signal.
    ///
    /// The scan stops at the first line bearing code, so a directive followed by
    /// unrelated code still targets that code rather than leaping to whatever
    /// the author might have meant. If nothing follows, the returned line is
    /// past the end and the directive is inert.
    ///
    /// - Parameter line: 1-based line of the directive.
    /// - Returns: 1-based line to suppress.
    static func nextCodeLine(after line: Int, in lines: [String]) -> Int {
        var candidate = line + 1
        while candidate <= lines.count {
            let trimmed = lines[candidate - 1].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, !trimmed.hasPrefix("//") { return candidate }
            candidate += 1
        }
        return line + 1
    }

    private static func closeDisableRegions(
        keys: [RuleIdentifier?],
        endLine: Int,
        ranges: inout SuppressedRanges,
        openDisables: inout [RuleIdentifier?: Int]
    ) {
        for key in keys {
            if let start = openDisables.removeValue(forKey: key) {
                appendRange(to: &ranges, key: key, start: start, end: endLine)
            }
        }
    }

    private static func appendSingleLineRange(
        keys: [RuleIdentifier?],
        line: Int,
        ranges: inout SuppressedRanges
    ) {
        for key in keys {
            appendRange(to: &ranges, key: key, start: line, end: line)
        }
    }

    private static func appendRange(
        to ranges: inout SuppressedRanges,
        key: RuleIdentifier?,
        start: Int,
        end: Int
    ) {
        guard start <= end else { return }
        ranges[key, default: []].append((start: start, end: end))
    }

    private static func isSuppressed(
        line: Int,
        rule: RuleIdentifier,
        in ranges: SuppressedRanges
    ) -> Bool {
        if let allRanges = ranges[nil],
           allRanges.contains(where: { line >= $0.start && line <= $0.end }) {
            return true
        }
        if let ruleRanges = ranges[rule],
           ruleRanges.contains(where: { line >= $0.start && line <= $0.end }) {
            return true
        }
        return false
    }
}

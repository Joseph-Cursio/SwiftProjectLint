import SwiftProjectLintModels
import Foundation

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

        let lineCount = fileContent.components(separatedBy: "\n").count
        let ranges = buildSuppressedRanges(from: directives, lineCount: lineCount)

        return issues.filter { !isSuppressed(line: $0.lineNumber, rule: $0.ruleName, in: ranges) }
    }

    // MARK: - Private

    /// Maps a rule (nil = all rules) to the closed line ranges where it is suppressed.
    private typealias SuppressedRanges = [RuleIdentifier?: [(start: Int, end: Int)]]

    private static func buildSuppressedRanges(
        from directives: [SuppressionDirective],
        lineCount: Int
    ) -> SuppressedRanges {
        var ranges: SuppressedRanges = [:]
        // Open disable regions: key → start line. nil key means "all rules".
        var openDisables: [RuleIdentifier?: Int] = [:]

        for directive in directives.sorted(by: { $0.line < $1.line }) {
            // An empty rules set targets all rules, represented by a nil dictionary key.
            let keys: [RuleIdentifier?] = directive.rules.isEmpty
                ? [nil]
                : directive.rules.map { Optional($0) }

            switch directive.kind {
            case .disable:
                for key in keys where openDisables[key] == nil {
                    openDisables[key] = directive.line
                }
            case .enable:
                for key in keys {
                    if let start = openDisables.removeValue(forKey: key) {
                        appendRange(to: &ranges, key: key, start: start, end: directive.line - 1)
                    }
                }
            case .disableNext:
                for key in keys {
                    appendRange(to: &ranges, key: key, start: directive.line + 1, end: directive.line + 1)
                }
            case .disableThis:
                for key in keys {
                    appendRange(to: &ranges, key: key, start: directive.line, end: directive.line)
                }
            }
        }

        // Close any regions still open at end of file
        for (key, start) in openDisables {
            appendRange(to: &ranges, key: key, start: start, end: lineCount)
        }

        return ranges
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

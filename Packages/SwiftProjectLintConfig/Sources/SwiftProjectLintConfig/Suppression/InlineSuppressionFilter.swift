import SwiftProjectLintModels
import Foundation

/// Filters lint issues according to inline suppression comments in the source file.
///
/// Inline suppression only applies to per-file issues. Cross-file issues (e.g. duplicate
/// state across view hierarchies) are not affected, as their line numbers span multiple
/// files and a single-file comment cannot unambiguously reference them.
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

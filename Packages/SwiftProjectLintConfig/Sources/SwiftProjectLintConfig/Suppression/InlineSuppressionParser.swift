import Foundation
import SwiftProjectLintModels

/// A parsed inline suppression directive from a Swift source comment.
public struct SuppressionDirective: Sendable {
    public enum Kind: Sendable {
        /// Disables rule(s) from this line forward until a matching `enable`.
        case disable
        /// Re-enables rule(s) that were previously disabled.
        case enable
        /// Disables rule(s) for the next line only.
        case disableNext
        /// Disables rule(s) for this line only.
        case disableThis
    }

    /// The kind of directive.
    public let kind: Kind
    /// Rules this directive resolved. **Empty does not mean "all rules"** — see
    /// `targetsAllRules`, which is the question callers actually want answered.
    public let rules: Set<RuleIdentifier>
    /// Tokens that matched no rule, in source order.
    ///
    /// Kept rather than dropped so a directive that named *nothing* can be told
    /// from one that named only things this build does not recognise. Collapsing
    /// the two made the second silently take the first's meaning: every rule
    /// disabled, by a comment that reads as naming one.
    public let unrecognizedNames: [String]
    /// 1-based line number of the comment in the source file.
    public let line: Int

    /// Whether this directive targets every rule — true only when it named no
    /// rules at all, which is the documented spelling of "suppress everything".
    ///
    /// A directive whose every name failed to resolve targets **nothing**. That
    /// is the conservative reading: the author meant a specific rule, and a
    /// build that cannot tell which one should not answer "then all of them".
    public var targetsAllRules: Bool {
        rules.isEmpty && unrecognizedNames.isEmpty
    }
}

/// Parses inline suppression comments from Swift source.
///
/// Supported syntax:
/// ```swift
/// // swiftprojectlint:disable rule-name
/// // swiftprojectlint:enable rule-name
/// // swiftprojectlint:disable:next rule-name
/// // swiftprojectlint:disable:this rule-name
/// ```
///
/// Multiple rule names can appear space-separated on one line.
/// Omitting rule names targets all rules:
/// ```swift
/// // swiftprojectlint:disable
/// ```
///
/// Rule names use the kebab-case form of `RuleIdentifier.suppressionKey`,
/// e.g. `force-try`, `fat-view-detection`, `magic-number`.
public struct InlineSuppressionParser {
    private static let commentPrefix = "// swiftprojectlint:"

    private static let keyToRule: [String: RuleIdentifier] = {
        Dictionary(uniqueKeysWithValues: RuleIdentifier.allCases.map { ($0.suppressionKey, $0) })
    }()

    /// Parses all suppression directives found in `fileContent`.
    public static func parse(fileContent: String) -> [SuppressionDirective] {
        var directives: [SuppressionDirective] = []
        let lines = fileContent.components(separatedBy: "\n")

        for (index, rawLine) in lines.enumerated() {
            let lineNumber = index + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(commentPrefix) else { continue }

            let rest = String(trimmed.dropFirst(commentPrefix.count))
            guard let (kind, rulesPart) = parseKindAndRules(from: rest) else { continue }

            let parsed = parseRules(from: rulesPart)
            directives.append(SuppressionDirective(
                kind: kind,
                rules: parsed.rules,
                unrecognizedNames: parsed.unrecognized,
                line: lineNumber
            ))
        }

        return directives
    }

    // MARK: - Private

    private static func parseKindAndRules(from rest: String) -> (SuppressionDirective.Kind, String)? {
        let directives: [(String, SuppressionDirective.Kind)] = [
            ("disable:next", .disableNext),
            ("disable:this", .disableThis),
            ("disable", .disable),
            ("enable", .enable)
        ]
        for (keyword, kind) in directives {
            if rest == keyword {
                return (kind, "")
            }
            if rest.hasPrefix(keyword + " ") {
                let rules = String(rest.dropFirst(keyword.count + 1))
                return (kind, rules)
            }
        }
        return nil
    }

    /// Splits the names on a directive into the rules they resolve to and the
    /// tokens that resolve to nothing.
    ///
    /// An unknown token is still ignored *as a rule* — a file naming a rule a
    /// newer build has must not fail on an older one, which is why they were
    /// dropped in the first place. What changes is that they are no longer
    /// forgotten: a directive left with no rules and some unrecognised names is
    /// a different thing from one that named nothing, and `targetsAllRules`
    /// keeps them apart.
    private static func parseRules(
        from rulesPart: String
    ) -> (rules: Set<RuleIdentifier>, unrecognized: [String]) {
        let tokens = rulesPart.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var rules: Set<RuleIdentifier> = []
        var unrecognized: [String] = []
        for token in tokens {
            if let rule = keyToRule[token.lowercased()] {
                rules.insert(rule)
            } else {
                unrecognized.append(token)
            }
        }
        return (rules, unrecognized)
    }
}

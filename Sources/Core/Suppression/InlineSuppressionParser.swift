import Foundation

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
    /// Rules targeted by this directive. An empty set means "all rules".
    public let rules: Set<RuleIdentifier>
    /// 1-based line number of the comment in the source file.
    public let line: Int
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

            let rules = parseRules(from: rulesPart)
            directives.append(SuppressionDirective(kind: kind, rules: rules, line: lineNumber))
        }

        return directives
    }

    // MARK: - Private

    private static func parseKindAndRules(from rest: String) -> (SuppressionDirective.Kind, String)? {
        let directives: [(String, SuppressionDirective.Kind)] = [
            ("disable:next", .disableNext),
            ("disable:this", .disableThis),
            ("disable",      .disable),
            ("enable",       .enable)
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

    private static func parseRules(from rulesPart: String) -> Set<RuleIdentifier> {
        let tokens = rulesPart.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var rules: Set<RuleIdentifier> = []
        for token in tokens {
            if let rule = keyToRule[token.lowercased()] {
                rules.insert(rule)
            }
            // Unknown tokens are silently ignored — future rules won't break old files
        }
        return rules
    }
}

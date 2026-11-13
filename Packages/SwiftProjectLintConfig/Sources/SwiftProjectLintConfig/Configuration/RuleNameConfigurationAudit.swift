import Foundation
import SwiftProjectLintModels
import Yams

/// Mistakes in a `.swiftprojectlint.yml` that change which rules run, without saying so.
///
/// `LintConfigurationLoader` drops what it cannot use, and each drop fails quietly:
/// - A rule name that matches no rule is skipped. Under `disabled_rules` the rule keeps running;
///   under `rules:` its override never applies.
/// - Under `enabled_only` the same skip can leave the list empty, and an empty `enabled_only` runs
///   **no rules at all**. The run then reports nothing and exits 0. A CI gate configured that way
///   passes while checking nothing, and a typo or a removed rule is enough to cause it.
/// - A rule list written as a single string instead of a list is read as an empty list.
/// - `enabled_only` is ignored outright when `disabled_rules` names a known rule.
/// - A `--config` file that does not exist, or is not a YAML mapping, falls back to the defaults.
///
/// This reads the file again rather than changing what the loader returns, the same way the CLI's
/// other audits work: the loader's result has many callers, and none of them needs the diagnosis.
public enum RuleNameConfigurationAudit {

    public enum Problem: Equatable, Sendable {
        /// An entry under `key` naming no rule, with the rule it most likely meant.
        case unknownRule(key: String, name: String, suggestion: String?)
        /// `key` holds something other than a list of strings, so it is read as empty.
        case notAList(key: String)
        /// `enabled_only` is present but names no known rule, so the run checks nothing.
        case enabledOnlyRunsNothing
        /// `enabled_only` is present but ignored, because `disabled_rules` names a known rule.
        case enabledOnlyIgnored
        /// The explicitly given configuration file does not exist.
        case fileNotFound(path: String)
        /// The configuration file exists but is not a YAML mapping.
        case unreadable(path: String)
    }

    /// The keys whose entries are rule names: two lists, and the map of per-rule overrides.
    static let ruleListKeys = ["disabled_rules", "enabled_only"]
    static let overridesKey = "rules"

    /// The problems in the configuration file at `path`.
    ///
    /// - Parameter explicit: whether the user named this file (`--config`). A missing default
    ///   `.swiftprojectlint.yml` is normal; a missing file the user asked for is not.
    public static func problems(atPath path: String, explicit: Bool) -> [Problem] {
        guard FileManager.default.fileExists(atPath: path) else {
            return explicit ? [.fileNotFound(path: path)] : []
        }
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [.unreadable(path: path)]
        }
        return problems(inYAML: content, path: path)
    }

    /// The problems in `content`, read as a configuration file at `path`.
    public static func problems(inYAML content: String, path: String) -> [Problem] {
        // A file with no content, only comments, or a bare `---` holds no settings. The loader treats
        // that as the default configuration, which is what an empty file means, so it is not a problem.
        let document: Any?
        do {
            document = try Yams.load(yaml: content)
        } catch {
            return [.unreadable(path: path)]
        }
        // `---` alone is a document holding null rather than no document; it means the same.
        guard let document, (document is NSNull) == false else { return [] }
        guard let yaml = document as? [String: Any] else {
            return [.unreadable(path: path)]
        }

        return unknownNames(in: yaml) + enabledOnlyProblems(in: yaml)
    }

    /// Rule names that match no rule, and rule lists that are not lists, in key order.
    private static func unknownNames(in yaml: [String: Any]) -> [Problem] {
        var problems: [Problem] = []
        for key in ruleListKeys {
            guard let value = yaml[key] else { continue }
            // YAML `key:` with nothing after it is null, read as an empty list; not a malformed one.
            if value is NSNull { continue }
            guard let names = value as? [String] else {
                problems.append(.notAList(key: key))
                continue
            }
            for name in names where isRule(name) == false {
                problems.append(.unknownRule(key: key, name: name, suggestion: suggestion(for: name)))
            }
        }
        if let overrides = yaml[overridesKey] as? [String: Any] {
            for name in overrides.keys.sorted() where isRule(name) == false {
                problems.append(.unknownRule(key: overridesKey, name: name, suggestion: suggestion(for: name)))
            }
        }
        return problems
    }

    /// Whether `enabled_only` is ignored, or runs nothing.
    ///
    /// The loader treats any present `enabled_only`, even `enabled_only:` with nothing after it,
    /// as the list of rules to run, so one naming no rule runs nothing. It ignores `enabled_only`
    /// only when `disabled_rules` resolves to at least one identifier: unknown names are dropped
    /// first, so `disabled_rules: ["Typo"]` leaves `enabled_only` in force.
    private static func enabledOnlyProblems(in yaml: [String: Any]) -> [Problem] {
        guard let enabledOnly = yaml["enabled_only"] else { return [] }
        let disabledRules = ((yaml["disabled_rules"] as? [String]) ?? []).filter { RuleIdentifier(rawValue: $0) != nil }
        if disabledRules.isEmpty == false {
            return [.enabledOnlyIgnored]
        }
        if ((enabledOnly as? [String]) ?? []).contains(where: isRule) == false {
            return [.enabledOnlyRunsNothing]
        }
        return []
    }

    /// Whether `name` is a rule a configuration can select.
    ///
    /// The sentinels `Unknown` and `File Parsing Error` resolve to identifiers, so the loader keeps
    /// them, but they name no rule: `LintConfiguration.resolveRules` starts from
    /// `RuleIdentifier.selectableRules` and drops them. An `enabled_only` listing only a sentinel
    /// therefore runs nothing, just like one listing a typo.
    static func isRule(_ name: String) -> Bool {
        RuleIdentifier(rawValue: name).map(RuleIdentifier.selectableRules.contains) ?? false
    }

    /// Selectable rules in display-name order, so the first suggestion that fits is always the same one.
    private static let suggestable = RuleIdentifier.selectableRules.sorted { $0.rawValue < $1.rawValue }

    /// The rule display name `name` probably meant, or `nil`.
    ///
    /// Compares letters and digits only, ignoring case, so `magic-number`, `magic_number` and
    /// `MagicNumber` all find `Magic Number`. The suppression key is tried as well as the display
    /// name, since a config author may copy the key from a `disable` comment.
    public static func suggestion(for name: String) -> String? {
        let needle = normalized(name)
        guard needle.isEmpty == false else { return nil }
        return suggestable.first { rule in
            normalized(rule.rawValue) == needle || normalized(rule.suppressionKey) == needle
        }?.rawValue
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// The notice for stderr: one line per problem.
    public static func notice(for problems: [Problem], path: String) -> String {
        let lines = problems.map { problem -> String in
            switch problem {
            case let .unknownRule(key, name, suggestion):
                let tail = suggestion.map { " Did you mean '\($0)'?" } ?? " No rule has that name."
                return "  \(key): '\(name)' is not a rule, so it is ignored.\(tail)"

            case let .notAList(key):
                return "  \(key): expected a list of rule names, so it is read as empty."

            case .enabledOnlyRunsNothing:
                return "  enabled_only: names no known rule, so this run checks nothing."

            case .enabledOnlyIgnored:
                return "  enabled_only: ignored, because disabled_rules is also set."

            case let .fileNotFound(path):
                return "  \(path): no such file, so the default configuration is used."

            case let .unreadable(path):
                return "  \(path): not a YAML mapping, so the default configuration is used."
            }
        }
        let one = problems.count == 1
        var notice = """
            Warning: \(path) has \(problems.count) problem\(one ? "" : "s") \
            that change\(one ? "s" : "") which rules run.
            \(lines.joined(separator: "\n"))
            """
        if problems.contains(where: { if case .unknownRule = $0 { true } else { false } }) {
            notice += "\nRule names are the display names listed in Docs/rules/RULES.md, such as 'Magic Number'."
        }
        return notice
    }
}

import Foundation
import Yams

/// Loads a `LintConfiguration` from a YAML file.
///
/// The expected YAML structure:
/// ```yaml
/// disabled_rules:
///   - "Magic Number"
///   - "Print Statement"
///
/// # OR (mutually exclusive with disabled_rules):
/// # enabled_only:
/// #   - "Force Unwrap"
///
/// excluded_paths:
///   - "Tests/"
///   - "Generated/"
///
/// rules:
///   "Hardcoded Strings":
///     severity: info
///     excluded_paths:
///       - "Resources/"
/// ```
public struct LintConfigurationLoader {

    /// The default config file name searched in the project root.
    public static let defaultFileName = ".swiftprojectlint.yml"

    /// Loads configuration from a YAML file at the given path.
    /// Returns `.default` if the file doesn't exist or can't be parsed.
    public static func load(from path: String) -> LintConfiguration {
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8),
              let yaml = try? Yams.load(yaml: content) as? [String: Any] else {
            return .default
        }

        return parse(yaml: yaml)
    }

    /// Loads configuration from the default location in a project directory.
    public static func load(projectRoot: String) -> LintConfiguration {
        let path = (projectRoot as NSString).appendingPathComponent(defaultFileName)
        return load(from: path)
    }

    // MARK: - Parsing

    private static func parse(yaml: [String: Any]) -> LintConfiguration {
        let disabledRules = parseRuleList(yaml["disabled_rules"])
        let excludedPaths = parseStringList(yaml["excluded_paths"])
        let ruleOverrides = parseRuleOverrides(yaml["rules"])

        // enabled_only is nil when the key is absent; only set when explicitly provided
        let enabledOnlyRules: Set<RuleIdentifier>?
        if yaml["enabled_only"] != nil {
            let parsed = parseRuleList(yaml["enabled_only"])
            // Mutual exclusivity: disabled_rules takes precedence
            enabledOnlyRules = disabledRules.isEmpty ? parsed : nil
        } else {
            enabledOnlyRules = nil
        }

        return LintConfiguration(
            disabledRules: disabledRules,
            enabledOnlyRules: enabledOnlyRules,
            excludedPaths: excludedPaths,
            ruleOverrides: ruleOverrides
        )
    }

    private static func parseRuleList(_ value: Any?) -> Set<RuleIdentifier> {
        guard let names = value as? [String] else { return [] }
        var rules: Set<RuleIdentifier> = []
        for name in names {
            if let rule = RuleIdentifier(rawValue: name) {
                rules.insert(rule)
            }
        }
        return rules
    }

    private static func parseStringList(_ value: Any?) -> [String] {
        (value as? [String]) ?? []
    }

    private static func parseRuleOverrides(_ value: Any?) -> [RuleIdentifier: LintConfiguration.RuleOverride] {
        guard let dict = value as? [String: Any] else { return [:] }
        var overrides: [RuleIdentifier: LintConfiguration.RuleOverride] = [:]

        for (name, config) in dict {
            guard let rule = RuleIdentifier(rawValue: name),
                  let ruleConfig = config as? [String: Any] else { continue }

            let severity = parseSeverity(ruleConfig["severity"])
            let excludedPaths = parseStringList(ruleConfig["excluded_paths"])

            overrides[rule] = LintConfiguration.RuleOverride(
                severity: severity,
                excludedPaths: excludedPaths
            )
        }

        return overrides
    }

    private static func parseSeverity(_ value: Any?) -> IssueSeverity? {
        guard let str = value as? String else { return nil }
        switch str.lowercased() {
        case "error": return .error
        case "warning": return .warning
        case "info": return .info
        default: return nil
        }
    }
}

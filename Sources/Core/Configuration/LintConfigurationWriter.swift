import Foundation

/// Writes a `LintConfiguration` to a YAML file.
public struct LintConfigurationWriter {

    /// Writes the configuration to a `.swiftprojectlint.yml` file at the given path.
    public static func write(_ config: LintConfiguration, to path: String) {
        var lines: [String] = []

        // disabled_rules
        if !config.disabledRules.isEmpty {
            lines.append("disabled_rules:")
            for rule in config.disabledRules.map(\.rawValue).sorted() {
                lines.append("  - \"\(rule)\"")
            }
            lines.append("")
        }

        // enabled_only
        if let enabledOnly = config.enabledOnlyRules {
            lines.append("enabled_only:")
            for rule in enabledOnly.map(\.rawValue).sorted() {
                lines.append("  - \"\(rule)\"")
            }
            lines.append("")
        }

        // excluded_paths
        if !config.excludedPaths.isEmpty {
            lines.append("excluded_paths:")
            for exclusion in config.excludedPaths {
                lines.append("  - \"\(exclusion)\"")
            }
            lines.append("")
        }

        // rules (per-rule overrides)
        if !config.ruleOverrides.isEmpty {
            lines.append("rules:")
            for (rule, override) in config.ruleOverrides.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let hasSeverity = override.severity != nil
                let hasPaths = !override.excludedPaths.isEmpty
                guard hasSeverity || hasPaths else { continue }

                lines.append("  \"\(rule.rawValue)\":")
                if let severity = override.severity {
                    lines.append("    severity: \(severityString(severity))")
                }
                if !override.excludedPaths.isEmpty {
                    lines.append("    excluded_paths:")
                    for exclusion in override.excludedPaths {
                        lines.append("      - \"\(exclusion)\"")
                    }
                }
            }
            lines.append("")
        }

        let content = lines.joined(separator: "\n")
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func severityString(_ severity: IssueSeverity) -> String {
        switch severity {
        case .error: return "error"
        case .warning: return "warning"
        case .info: return "info"
        }
    }
}

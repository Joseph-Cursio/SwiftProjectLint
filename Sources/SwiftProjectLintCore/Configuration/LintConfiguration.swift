import Foundation

/// Configuration for controlling which rules run and how they behave.
///
/// Loaded from a `.swiftprojectlint.yml` file in the target project, or constructed
/// programmatically. Supports disabling rules, restricting to specific rules,
/// excluding file paths, and per-rule severity/path overrides.
public struct LintConfiguration: Sendable {
    /// Rules to skip entirely.
    public let disabledRules: Set<RuleIdentifier>

    /// If non-nil, only these rules run (mutually exclusive with `disabledRules`).
    public let enabledOnlyRules: Set<RuleIdentifier>?

    /// File path patterns to exclude globally (matched against relative paths).
    public let excludedPaths: [String]

    /// Per-rule overrides for severity and path exclusions.
    public let ruleOverrides: [RuleIdentifier: RuleOverride]

    /// Per-rule configuration override.
    public struct RuleOverride: Sendable {
        public let severity: IssueSeverity?
        public let excludedPaths: [String]

        public init(severity: IssueSeverity? = nil, excludedPaths: [String] = []) {
            self.severity = severity
            self.excludedPaths = excludedPaths
        }
    }

    public init(
        disabledRules: Set<RuleIdentifier> = [],
        enabledOnlyRules: Set<RuleIdentifier>? = nil,
        excludedPaths: [String] = [],
        ruleOverrides: [RuleIdentifier: RuleOverride] = [:]
    ) {
        self.disabledRules = disabledRules
        self.enabledOnlyRules = enabledOnlyRules
        self.excludedPaths = excludedPaths
        self.ruleOverrides = ruleOverrides
    }

    /// Default configuration — all rules enabled, no exclusions.
    public static let `default` = LintConfiguration()

    /// Computes the effective set of rule identifiers to run, given optional CLI overrides.
    public func resolveRules(
        cliCategories: [PatternCategory]? = nil,
        cliRuleIdentifiers: [RuleIdentifier]? = nil
    ) -> [RuleIdentifier]? {
        // CLI rule identifiers take full precedence
        if let cliRuleIdentifiers {
            return cliRuleIdentifiers
        }

        var rules = Set(RuleIdentifier.allCases)
        rules.remove(.unknown)
        rules.remove(.fileParsingError)

        // enabled_only restricts to a specific set
        if let enabledOnly = enabledOnlyRules {
            rules = rules.intersection(enabledOnly)
        }

        // Remove disabled rules
        rules.subtract(disabledRules)

        // CLI categories further restrict
        if let cliCategories {
            rules = rules.filter { cliCategories.contains($0.category) }
        }

        // nil means "no filtering" — return nil if we haven't actually restricted anything
        let allRules = Set(RuleIdentifier.allCases).subtracting([.unknown, .fileParsingError])
        if rules == allRules && cliCategories == nil {
            return nil
        }

        return Array(rules)
    }

    /// Filters and transforms issues based on per-rule overrides (path exclusions, severity).
    public func applyOverrides(to issues: [LintIssue]) -> [LintIssue] {
        issues.compactMap { issue in
            guard let override = ruleOverrides[issue.ruleName] else { return issue }

            // Check per-rule path exclusions
            let excluded = override.excludedPaths.contains { pattern in
                issue.filePath.contains(pattern)
            }
            if excluded { return nil }

            // Apply severity override
            if let severity = override.severity {
                return LintIssue(
                    severity: severity,
                    message: issue.message,
                    locations: issue.locations,
                    suggestion: issue.suggestion,
                    ruleName: issue.ruleName
                )
            }

            return issue
        }
    }
}

import SwiftProjectLintModels
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

    /// Layer policies for the Architectural Boundary rule.
    ///
    /// Empty by default — the rule is a no-op unless at least one layer is configured.
    /// Only meaningful for single-target apps; modular projects rely on the compiler.
    public let architecturalLayers: [LayerPolicy]

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
        ruleOverrides: [RuleIdentifier: RuleOverride] = [:],
        architecturalLayers: [LayerPolicy] = []
    ) {
        self.disabledRules = disabledRules
        self.enabledOnlyRules = enabledOnlyRules
        self.excludedPaths = excludedPaths
        self.ruleOverrides = ruleOverrides
        self.architecturalLayers = architecturalLayers
    }

    /// Rules that are opt-in only — disabled unless explicitly enabled via `enabled_only`.
    public static let optInRules: Set<RuleIdentifier> = [
        .magicLayoutNumber,
        .nonActorAgentSuffix,
        .hardcodedStrings,
        .testMissingAssertion,
        .testMissingExpect,
        .testMissingRequire
    ]

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
        } else {
            // Remove opt-in rules unless explicitly kept (not in disabledRules means
            // the user hasn't mentioned them at all — they stay off by default)
            rules.subtract(Self.optInRules)
        }

        // Remove disabled rules
        rules.subtract(disabledRules)

        // CLI categories further restrict
        if let cliCategories {
            rules = rules.filter { cliCategories.contains($0.category) }
        }

        // nil means "no filtering" — return nil if we haven't actually restricted anything
        let allRules = Set(RuleIdentifier.allCases)
            .subtracting([.unknown, .fileParsingError])
            .subtracting(Self.optInRules)
        if rules == allRules && cliCategories == nil {
            return nil
        }

        return Array(rules)
    }

    /// Filters and transforms issues based on per-rule overrides (path exclusions, severity).
    ///
    /// - Parameters:
    ///   - issues: The detected lint issues.
    ///   - projectRoot: The project root path, used to locate source files for path matching.
    public func applyOverrides(to issues: [LintIssue], projectRoot: String? = nil) -> [LintIssue] {
        guard !ruleOverrides.isEmpty else { return issues }

        // Build a lookup from basename → full relative path for path matching.
        // Issue file paths are basenames; excluded_paths patterns match relative paths.
        var basenameToRelativePath: [String: String] = [:]
        if let root = projectRoot {
            let allFiles = FileAnalysisUtils.findSwiftFiles(in: root)
            // Resolve symlinks so the prefix matches the canonical paths returned by findSwiftFiles.
            // FileManager.enumerator resolves symlinks in item paths (e.g. /var → /private/var on
            // macOS), so an unresolved root prefix would fail the hasPrefix check.
            let resolvedRoot = FileAnalysisUtils.realPath(root)
            let prefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
            for fullPath in allFiles {
                let basename = (fullPath as NSString).lastPathComponent
                let relative = fullPath.hasPrefix(prefix)
                    ? String(fullPath.dropFirst(prefix.count))
                    : fullPath
                basenameToRelativePath[basename] = relative
            }
        }

        return issues.compactMap { issue in
            guard let override = ruleOverrides[issue.ruleName] else { return issue }

            // Check per-rule path exclusions against the relative path
            if !override.excludedPaths.isEmpty {
                let relativePath = basenameToRelativePath[issue.filePath] ?? issue.filePath
                let basename = (relativePath as NSString).lastPathComponent
                let excluded = override.excludedPaths.contains { pattern in
                    Self.pathMatches(relativePath: relativePath, basename: basename, pattern: pattern)
                }
                if excluded { return nil }
            }

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

    /// Matches a file path against an exclusion pattern.
    ///
    /// Supports three styles:
    /// - `**/` prefix glob: `**/*View.swift` matches any file ending in `View.swift`
    /// - `*` glob without `**/`: matched via `fnmatch` against the relative path
    /// - Plain string: matched via `contains` against the relative path (e.g., `Tests/`)
    private static func pathMatches(relativePath: String, basename: String, pattern: String) -> Bool {
        if pattern.hasPrefix("**/") {
            // Strip **/ and match the remainder against the basename using fnmatch
            let basenamePattern = String(pattern.dropFirst(3))
            return fnmatch(basenamePattern, basename, 0) == 0
        } else if pattern.contains("*") {
            // General glob — match against the full relative path
            return fnmatch(pattern, relativePath, 0) == 0
        } else {
            // Simple substring match
            return relativePath.contains(pattern)
        }
    }
}

import Foundation
import SwiftProjectLintModels

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

    /// Filenames to exclude globally, matched against the file's basename only and
    /// compared exactly — no substring or glob matching.
    ///
    /// `excludedPaths` already covers location ("everything under `Generated/`") and,
    /// through its `**/` form, name-shaped globs. This covers the case where the same
    /// filename recurs all over a tree and the violations in it are intended wherever it
    /// appears — `Deprecations.swift`, `Constants.swift` — so listing the directories
    /// would mean enumerating them and revisiting the list whenever one is added.
    public let excludedFilenames: [String]

    /// Per-rule overrides for severity and path exclusions.
    public let ruleOverrides: [RuleIdentifier: RuleOverride]

    /// Layer policies for the Architectural Boundary rule.
    ///
    /// Empty by default — the rule is a no-op unless at least one layer is configured.
    /// Only meaningful for single-target apps; modular projects rely on the compiler.
    public let architecturalLayers: [LayerPolicy]

    /// Optional per-framework opt-in/out for the idempotency heuristic
    /// allowlists (round-14). `nil` (default) means "all known frameworks
    /// enabled" — the import-gating in `HeuristicEffectInferrer` still
    /// applies so a framework's allowlist only fires when the file
    /// imports its module.
    ///
    /// Setting this to a non-nil set restricts allowlist activity to the
    /// listed frameworks (using `FrameworkAllowlist` constants like
    /// `Foundation`, `NIOCore`, `Logging`, `Metrics`, etc.). Adopters
    /// who want to disable a specific framework's classifications —
    /// for example, because their codebase has a user-defined
    /// `class Counter` that shouldn't classify as observational —
    /// can omit the framework name from the set.
    public let enabledFrameworkAllowlists: Set<String>?

    /// When `true`, nested first-party Swift packages (directories with their
    /// own `Package.swift`, outside build/dependency directories) are analyzed
    /// in the same run rather than skipped. This lets cross-file rules span the
    /// package boundary, at the cost of linting those packages under this
    /// configuration rather than their own. Defaults to `false`.
    public let includeNestedPackages: Bool

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
        excludedFilenames: [String] = [],
        ruleOverrides: [RuleIdentifier: RuleOverride] = [:],
        architecturalLayers: [LayerPolicy] = [],
        enabledFrameworkAllowlists: Set<String>? = nil,
        includeNestedPackages: Bool = false
    ) {
        self.disabledRules = disabledRules
        self.enabledOnlyRules = enabledOnlyRules
        self.excludedPaths = excludedPaths
        self.excludedFilenames = excludedFilenames
        self.ruleOverrides = ruleOverrides
        self.architecturalLayers = architecturalLayers
        self.enabledFrameworkAllowlists = enabledFrameworkAllowlists
        self.includeNestedPackages = includeNestedPackages
    }

    /// Returns a copy with `includeNestedPackages` overridden — used to apply a
    /// CLI flag on top of a loaded configuration.
    public func withIncludeNestedPackages(_ value: Bool) -> Self {
        Self(
            disabledRules: disabledRules,
            enabledOnlyRules: enabledOnlyRules,
            excludedPaths: excludedPaths,
            excludedFilenames: excludedFilenames,
            ruleOverrides: ruleOverrides,
            architecturalLayers: architecturalLayers,
            enabledFrameworkAllowlists: enabledFrameworkAllowlists,
            includeNestedPackages: value
        )
    }

    /// Rules that are opt-in only — disabled unless explicitly enabled via `enabled_only`.
    public static let optInRules: Set<RuleIdentifier> = [
        .magicLayoutNumber,
        .nonActorAgentSuffix,
        .hardcodedStrings,
        .testMissingAssertion,
        .testMissingExpect,
        .testMissingRequire,
        .duplicateStructShape,
        .sharedDomainEnumField,
        .primitiveBypassingItsDomainType,
        .primitiveNamedForItsDomainType,
        .scatteredEnumMapping,
        .duplicateEnumMapping,
        .parallelEnumShape,
        .couldAdoptProtocol,
        .hoistableConformerMember,
        .hoistableSequenceOperation,
        .mutuallyExclusivePresentationState,
        .flagOptionalPairState,
        .redundantDerivedProperty,
        .animationWithoutReduceMotion,
        // Both of these were authored as opt-in — their rule docs say so, their
        // registrar descriptions say "Disabled by default", and the commits that
        // added them are titled "(opt-in)" — but neither was ever registered here,
        // so both ran by default. See Docs/rules/missing-dynamic-type-support.md
        // and Docs/rules/decorative-image-missing-trait.md for why each is
        // heuristic enough to warrant opting in.
        .missingDynamicTypeSupport,
        .decorativeImageMissingTrait,
        // Opt-in: `Slider(value:in:)` is the ordinary spelling, so this would fire
        // across most codebases on a default run.
        .unlabeledControl
    ]

    /// Default configuration — all rules enabled, no exclusions.
    public static let `default` = Self()

    /// Computes the effective set of rule identifiers to run, given optional CLI overrides.
    public func resolveRules(
        cliCategories: [PatternCategory]? = nil,
        cliRuleIdentifiers: [RuleIdentifier]? = nil
    ) -> [RuleIdentifier]? {
        // CLI rule identifiers take full precedence
        if let cliRuleIdentifiers {
            return cliRuleIdentifiers
        }

        // `selectableRules` is `allCases` minus the sentinels, and it exists so that the
        // definition of "a rule" is written once — its own doc records the README disagreeing
        // with the code by a quarter when it was re-derived inline. This was one of the sites
        // re-deriving it.
        var rules = RuleIdentifier.selectableRules

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

        // `nil` means "no filtering" to the caller — `ProjectLinter` passes it straight through
        // as `ruleIdentifiers`, where a nil runs every registered rule. So it may only be
        // returned when the resolved set really is every selectable rule.
        //
        // It used to compare against `selectableRules.subtracting(Self.optInRules)` — a set that
        // has already had the opt-in rules removed — so the test was true **precisely when the
        // set had been restricted**, by removing them, and the caller then ran the 25 rules it
        // was meant to exclude. A Swift-package root was immune only by accident:
        // `ProjectLinter+FileAnalysis` rebuilds the configuration with `.publicInAppTarget`
        // disabled, and that one insertion was enough to make the comparison false. An
        // Xcode-project root got no such rebuild and ran every opt-in rule by default —
        // 62% of one subject's findings (#217).
        if rules == RuleIdentifier.selectableRules, cliCategories == nil {
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
        if let givenRoot = projectRoot {
            let allFiles = FileAnalysisUtils.findSwiftFiles(in: givenRoot)
            // Canonicalised so the prefix matches the paths `findSwiftFiles` returns: the enumerator
            // spells item paths with the resolved root even when handed an unresolved one
            // (`/var` → `/private/var` on macOS). See `ProjectRoot`.
            let root = ProjectRoot(givenRoot)
            for fullPath in allFiles {
                let basename = (fullPath as NSString).lastPathComponent
                // Not under the root: match against the absolute path, which is the widest thing a
                // pattern can be tried on. A third fallback, and now a stated one -- the other two
                // callers of this derivation answer differently, because an exclusion that matches
                // too little is safer here than one that matches the wrong relative path.
                let relative = root.relativePath(of: fullPath)?.value ?? fullPath
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

            // Apply severity override.
            //
            // Every field must be carried across explicitly: `LintIssue`'s
            // initialiser defaults `symbol` to nil, so omitting it here does not
            // downgrade a seed — `PBTSeedsFormatter` drops symbol-less issues
            // outright, which silently empties the seed manifest for any rule a
            // user configures a severity on. This is exactly the shape the
            // `lossyStructRebuild` rule exists to flag; keep it exhaustive.
            //
            // **The comment was right and the code had drifted anyway.** It was
            // written when `symbol` was the only seed-bearing field, and stayed
            // accurate in spirit while `role` and `testReachability` were added
            // above it and silently dropped here — so configuring a severity on
            // `pureFunctionCandidate` cost the manifest its role classification
            // and its restriction remedy, leaving the seed present but stripped
            // of everything a consumer acts on. A warning to be exhaustive does
            // not stay true by itself; only the enumeration does.
            if let severity = override.severity {
                return LintIssue(
                    severity: severity,
                    message: issue.message,
                    locations: issue.locations,
                    suggestion: issue.suggestion,
                    ruleName: issue.ruleName,
                    symbol: issue.symbol,
                    role: issue.role,
                    effect: issue.effect,
                    testReachability: issue.testReachability
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
        }
        if pattern.contains("*") {
            // General glob — match against the full relative path
            return fnmatch(pattern, relativePath, 0) == 0
        }
        // Simple substring match
        return relativePath.contains(pattern)
    }
}

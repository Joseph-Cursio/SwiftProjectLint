import Foundation
import SwiftParser
import SwiftProjectLintConfig
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

extension ProjectLinter {
    /// Adjusts configuration for libraries: disables `publicInAppTarget`,
    /// excludes executable source paths from the `printStatement` rule, and suppresses
    /// `unusedProtocolAbstraction` when first-party nested packages are out of scope.
    ///
    /// - Parameters:
    ///   - path: The project root being analyzed.
    ///   - configuration: The configuration to adjust.
    ///   - targetType: Whether to treat the project as a library, an app, or to detect
    ///     it from the presence of a `Package.swift`. See ``TargetType``.
    static func resolveConfiguration(
        for path: String,
        base configuration: LintConfiguration,
        targetType: TargetType = .auto
    ) -> LintConfiguration {
        // `.auto` keeps the historical rule — a `Package.swift` beside the analyzed
        // path means library — so an existing run's behaviour is unchanged unless the
        // caller asks for something else.
        let isLibrary: Bool
        switch targetType {
        case .library:
            isLibrary = true

        case .app:
            isLibrary = false

        case .auto:
            isLibrary = FileManager.default.fileExists(
                atPath: PathString.appending("Package.swift", to: path)
            )
        }
        // A nested package that publishes a `.library` product is a library whatever the ROOT is,
        // and `include_nested_packages` pulls it into a run classified from the root. Excluding its
        // paths from `publicInAppTarget` is the same move the `printStatement` override below makes
        // for executable sources, and it has to happen before the library-root early return —
        // otherwise an app root (an `.xcodeproj` with a package beside it) never reaches it, which
        // is exactly the 462-finding case in #108.
        let libraryPaths = configuration.includeNestedPackages
            ? LibraryPackageDetector.libraryPackagePaths(in: path)
            : []

        // Executable sources, from the root manifest AND from nested packages. `print` to stdout
        // is a CLI's interface, not logging, and routing it to `os.Logger` would print nothing.
        //
        // Computed here for the reason the comment above gives about `publicInAppTarget`: it used
        // to sit after the early return, so an app root — an `.xcodeproj` with a package beside it
        // — never reached it. Five findings on `swiftumlbridge` for output the user asked for
        // (#112). The precedent this file cites for the library-path fix had the same defect.
        let execPaths = ExecutableTargetDetector.executableSourcePaths(in: path)
            + (configuration.includeNestedPackages
                ? ExecutableTargetDetector.nestedExecutableSourcePaths(in: path)
                : [])

        guard isLibrary else {
            return Self.excluding(
                libraryPaths: libraryPaths, executablePaths: execPaths, from: configuration
            )
        }

        var disabledRules = configuration.disabledRules
        disabledRules.insert(.publicInAppTarget)

        // `unusedProtocolAbstraction` reasons about whole-project usage: it flags a
        // protocol that is conformed to but never *used* as a type. If first-party
        // nested packages exist but are excluded from this run, a protocol consumed
        // only in a sibling package looks unused and is falsely flagged. Suppress it
        // unless the scope is complete — i.e. those packages are pulled in with
        // `includeNestedPackages`, or there are none. (A single-package project and a
        // `--include-nested-packages` whole-project run both keep the rule on.)
        if !configuration.includeNestedPackages,
           FileAnalysisUtils.containsNestedPackage(in: path) {
            disabledRules.insert(.unusedProtocolAbstraction)
        }

        var overrides = configuration.ruleOverrides
        if execPaths.isEmpty == false {
            let existing = overrides[.printStatement]
            overrides[.printStatement] = LintConfiguration.RuleOverride(
                severity: existing?.severity,
                excludedPaths: (existing?.excludedPaths ?? []) + execPaths
            )
        }
        return LintConfiguration(
            disabledRules: disabledRules,
            enabledOnlyRules: configuration.enabledOnlyRules,
            excludedPaths: configuration.excludedPaths,
            excludedFilenames: configuration.excludedFilenames,
            ruleOverrides: overrides,
            architecturalLayers: configuration.architecturalLayers,
            enabledFrameworkAllowlists: configuration.enabledFrameworkAllowlists,
            // Preserve the caller's nested-package opt-in: this rebuild only adjusts
            // package-specific rule defaults. Omitting it reset the flag to its `false`
            // default, silently making `--include-nested-packages` a no-op for every
            // Swift-package project (the only projects that reach this branch).
            includeNestedPackages: configuration.includeNestedPackages
        )
    }

    /// Narrows `publicInAppTarget` to the paths it applies to, by excluding nested library
    /// packages. Returns `configuration` untouched when there are none, so the common case pays
    /// nothing and an existing run's behaviour is unchanged.
    ///
    /// Path exclusion rather than a per-file target type: the rule is already suppressed by path
    /// for executables (`printStatement`), the mechanism is tested, and the alternative — resolving
    /// a `TargetType` per file — would put a filesystem walk behind every visitor.
    private static func excluding(
        libraryPaths: [String],
        executablePaths: [String],
        from configuration: LintConfiguration
    ) -> LintConfiguration {
        guard !libraryPaths.isEmpty || !executablePaths.isEmpty else { return configuration }

        var overrides = configuration.ruleOverrides
        if !libraryPaths.isEmpty {
            let existing = overrides[.publicInAppTarget]
            overrides[.publicInAppTarget] = LintConfiguration.RuleOverride(
                severity: existing?.severity,
                excludedPaths: (existing?.excludedPaths ?? []) + libraryPaths
            )
        }
        if !executablePaths.isEmpty {
            let existing = overrides[.printStatement]
            overrides[.printStatement] = LintConfiguration.RuleOverride(
                severity: existing?.severity,
                excludedPaths: (existing?.excludedPaths ?? []) + executablePaths
            )
        }
        return LintConfiguration(
            disabledRules: configuration.disabledRules,
            enabledOnlyRules: configuration.enabledOnlyRules,
            excludedPaths: configuration.excludedPaths,
            excludedFilenames: configuration.excludedFilenames,
            ruleOverrides: overrides,
            architecturalLayers: configuration.architecturalLayers,
            enabledFrameworkAllowlists: configuration.enabledFrameworkAllowlists,
            includeNestedPackages: configuration.includeNestedPackages
        )
    }
}

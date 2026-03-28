//
//  ContentViewModel.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 3/16/26.
//

import SwiftUI
import Core

/// View model that manages state and business logic for ContentView.
///
/// Extracted from ContentView to separate concerns: ContentView owns the view hierarchy,
/// while ContentViewModel owns state, persistence, and analysis orchestration.
@Observable
@MainActor
class ContentViewModel {
    var selectedDirectory: String = ""
    /// The security-scoped URL from the file picker — must be retained for access.
    var selectedDirectoryURL: URL?
    var isAnalyzing: Bool = false
    var lintIssues: [LintIssue] = []
    var showRuleSelector: Bool = false
    var enabledRuleNames: Set<RuleIdentifier> = {
        let userDefaultsKey = "enabledLintRules"
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(Set<RuleIdentifier>.self, from: data),
           !saved.isEmpty {
            return saved
        } else {
            return Set(RuleIdentifier.allCases)
        }
    }()
    var showingDirectoryPicker: Bool = false
    var analysisTask: Task<Void, Never>?

    /// Per-rule exclusion flags (Exclude Tests, Exclude *View.swift).
    var ruleExclusions: [RuleIdentifier: RuleExclusions] = [:]

    /// Whether the current GUI state differs from the loaded YAML config.
    var configIsDirty: Bool = false

    /// The configuration as loaded from the YAML file (for dirty tracking).
    private var loadedConfig: LintConfiguration?

    /// Injected reference to the pattern registry from SystemComponents.
    var patternRegistry: SourcePatternRegistryProtocol?

    /// Injected detector with populated registry from SystemComponents.
    var detector: (any SourcePatternDetectorProtocol)?

    /// The project analyzer used for linting. Defaults to `ProjectLinter`.
    /// Inject a mock conforming to `ProjectAnalyzerProtocol` for testing.
    var analyzer: any ProjectAnalyzerProtocol = ProjectLinter()

    private let userDefaultsKey = "enabledLintRules"

    // MARK: - Computed Properties

    /// Pattern configuration that uses SwiftSyntax for all categories.
    var allPatternsByCategory: [PatternCategoryInfo] {
        PatternConfiguration.allPatternsByCategory(from: patternRegistry)
    }

    // MARK: - Actions

    /// Save enabled rules to UserDefaults.
    func saveEnabledRules() {
        if let data = try? JSONEncoder().encode(enabledRuleNames) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    /// Opens the directory picker to select a project folder.
    func selectDirectory() {
        showingDirectoryPicker = true
    }

    /// Analyzes the selected project directory.
    func analyzeProject() {
        guard !selectedDirectory.isEmpty else { return }
        runLinter(at: selectedDirectory)
    }

    /// Cancels the current analysis task.
    func cancelAnalysis() {
        analysisTask?.cancel()
    }

    /// Determines which pattern categories have enabled rules.
    func getEnabledCategories() -> [PatternCategory] {
        PatternConfiguration.getEnabledCategories(
            patternRegistry: patternRegistry,
            enabledRuleNames: enabledRuleNames
        )
    }

    /// Filters lint issues to only include those from enabled rules using registry mapping.
    func filterIssuesByEnabledRules(_ issues: [LintIssue]) -> [LintIssue] {
        PatternConfiguration.filterIssuesByEnabledRules(issues, enabledRuleNames: enabledRuleNames)
    }

    // MARK: - Configuration

    /// Loads rule exclusions from a `.swiftprojectlint.yml` in the project directory.
    func loadConfigFromProject() {
        guard !selectedDirectory.isEmpty else { return }
        let config = LintConfigurationLoader.load(projectRoot: selectedDirectory)
        loadedConfig = config

        // Populate ruleExclusions from the loaded config's per-rule overrides
        var exclusions: [RuleIdentifier: RuleExclusions] = [:]
        for (rule, override) in config.ruleOverrides {
            var exc = RuleExclusions()
            exc.excludeTests = override.excludedPaths.contains { $0.contains("Tests/") }
            exc.excludeViews = override.excludedPaths.contains { $0.contains("*View.swift") }
            exclusions[rule] = exc
        }
        ruleExclusions = exclusions
        configIsDirty = false
    }

    /// Builds a `LintConfiguration` from the current GUI state.
    private func buildConfiguration() -> LintConfiguration {
        // Compute disabled rules (all rules not in enabledRuleNames)
        let allRules = Set(RuleIdentifier.allCases).subtracting([.unknown, .fileParsingError])
        let disabledRules = allRules.subtracting(enabledRuleNames)

        // Build per-rule overrides from exclusion checkboxes
        var overrides: [RuleIdentifier: LintConfiguration.RuleOverride] = [:]
        for (rule, exclusion) in ruleExclusions {
            var paths: [String] = []
            if exclusion.excludeTests { paths.append("Tests/") }
            if exclusion.excludeViews { paths.append("**/*View.swift") }
            if !paths.isEmpty {
                overrides[rule] = LintConfiguration.RuleOverride(excludedPaths: paths)
            }
        }

        // Preserve any severity overrides from the loaded config
        if let loaded = loadedConfig {
            for (rule, override) in loaded.ruleOverrides where override.severity != nil {
                let existing = overrides[rule]
                overrides[rule] = LintConfiguration.RuleOverride(
                    severity: override.severity,
                    excludedPaths: existing?.excludedPaths ?? override.excludedPaths
                )
            }
        }

        return LintConfiguration(
            disabledRules: disabledRules,
            ruleOverrides: overrides
        )
    }

    /// Saves the current GUI state to `.swiftprojectlint.yml` in the project directory.
    func saveConfigToProject() {
        guard !selectedDirectory.isEmpty else { return }
        let config = buildConfiguration()
        let path = (selectedDirectory as NSString)
            .appendingPathComponent(LintConfigurationLoader.defaultFileName)
        LintConfigurationWriter.write(config, to: path)
        loadedConfig = config
        configIsDirty = false
    }

    /// Updates the dirty flag by comparing current state to the loaded config.
    func updateDirtyState() {
        let current = buildConfiguration()
        if let loaded = loadedConfig {
            configIsDirty = current.disabledRules != loaded.disabledRules
                || current.ruleOverrides.keys != loaded.ruleOverrides.keys
                || current.ruleOverrides.contains { rule, override in
                    loaded.ruleOverrides[rule]?.excludedPaths != override.excludedPaths
                }
        } else {
            // No YAML file exists — dirty if any exclusions are set
            configIsDirty = !ruleExclusions.isEmpty
                && ruleExclusions.values.contains { $0.excludeTests || $0.excludeViews }
        }
    }

    // MARK: - Private

    /// Runs the project linter analysis at the given directory path.
    private func runLinter(at path: String) {
        guard !isAnalyzing else { return }

        analysisTask?.cancel()
        isAnalyzing = true

        let configuration = buildConfiguration()

        let enabledRules = Array(enabledRuleNames)
        let scopedURL = selectedDirectoryURL
        nonisolated(unsafe) let capturedDetector = detector
        let capturedAnalyzer = analyzer
        analysisTask = Task {
            let didAccess = scopedURL?.startAccessingSecurityScopedResource() ?? false
            defer {
                if didAccess { scopedURL?.stopAccessingSecurityScopedResource() }
            }

            let issues = await capturedAnalyzer.analyzeProject(
                at: path,
                categories: nil,
                ruleIdentifiers: enabledRules,
                detector: capturedDetector,
                configuration: configuration
            )

            guard !Task.isCancelled else {
                isAnalyzing = false
                return
            }

            lintIssues = issues
            isAnalyzing = false
        }
    }
}

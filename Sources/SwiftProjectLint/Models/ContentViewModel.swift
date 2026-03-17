//
//  ContentViewModel.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 3/16/26.
//

import Combine
import SwiftUI
import SwiftProjectLintCore

/// View model that manages state and business logic for ContentView.
///
/// Extracted from ContentView to separate concerns: ContentView owns the view hierarchy,
/// while ContentViewModel owns state, persistence, and analysis orchestration.
@MainActor
class ContentViewModel: ObservableObject {
    @Published var selectedDirectory: String = ""
    @Published var isAnalyzing: Bool = false
    @Published var lintIssues: [LintIssue] = []
    @Published var showRuleSelector: Bool = false
    @Published var enabledRuleNames: Set<RuleIdentifier> = {
        let userDefaultsKey = "enabledLintRules"
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(Set<RuleIdentifier>.self, from: data),
           !saved.isEmpty {
            return saved
        } else {
            return [.relatedDuplicateStateVariable]
        }
    }()
    @Published var showingDirectoryPicker: Bool = false
    var analysisTask: Task<Void, Never>?

    /// Injected reference to the pattern registry from SystemComponents.
    var patternRegistry: SourcePatternRegistryProtocol?

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

    // MARK: - Private

    /// Runs the project linter analysis at the given directory path.
    private func runLinter(at path: String) {
        guard !isAnalyzing else { return }

        analysisTask?.cancel()
        isAnalyzing = true

        analysisTask = Task {
            var allIssues: [LintIssue] = []

            let enabledCategories = getEnabledCategories()

            if !enabledCategories.isEmpty {
                let linter = ProjectLinter()
                let crossFileIssues = await linter.analyzeProject(at: path, categories: enabledCategories)

                guard !Task.isCancelled else {
                    isAnalyzing = false
                    return
                }

                allIssues.append(contentsOf: crossFileIssues)
            }

            lintIssues = allIssues
            isAnalyzing = false
        }
    }
}

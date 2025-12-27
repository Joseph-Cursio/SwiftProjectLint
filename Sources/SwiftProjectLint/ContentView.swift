//
//  ContentView.swift
//  SwiftProjectLint
//
//  Created by Joseph Cursio on 7/1/25.
//

import SwiftUI
import SwiftProjectLintCore
import UniformTypeIdentifiers

/// The main content view for the SwiftProjectLint application.
///
/// `ContentView` provides the primary user interface for the SwiftUI project linter,
/// featuring a clean, modern design with project selection, rule configuration,
/// and comprehensive linting results display.
///
/// The view delegates linting to a `ProjectLinter` instance and patterns defined in `SourcePatternRegistry`.
/// It uses SwiftSyntax-based pattern detection for improved accuracy across all categories.
///
/// Key Features:
/// - Project directory selection via native macOS file picker
/// - Configurable lint rule selection with 9 categories
/// - Real-time analysis with progress indicators
/// - Expandable results with detailed issue information
/// - Persistent rule preferences across app launches
struct ContentView: View {
    @EnvironmentObject var systemComponents: SystemComponents
    @State private var selectedDirectory: String = ""
    @State private var isAnalyzing: Bool = false
    @State private var lintIssues: [LintIssue] = []
    @State private var showRuleSelector: Bool = false
    @State private var enabledRuleNames: Set<RuleIdentifier> = {
        let userDefaultsKey = "enabledLintRules"
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(Set<RuleIdentifier>.self, from: data),
           !saved.isEmpty {
            return saved
        } else {
            return [.relatedDuplicateStateVariable]
        }
    }()
    @State private var showingDirectoryPicker: Bool = false

    private let userDefaultsKey = "enabledLintRules"

    // MARK: - Computed Properties

    /// Pattern configuration that uses SwiftSyntax for all categories.
    private var allPatternsByCategory: [PatternCategoryInfo] {
        PatternConfiguration.allPatternsByCategory(from: systemComponents.patternRegistry)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                ContentViewHeader()

                // Action Buttons
                ContentViewActions(
                    selectedDirectory: selectedDirectory,
                    onSelectRules: { showRuleSelector = true },
                    onSelectDirectory: selectDirectory,
                    onAnalyzeProject: analyzeProject
                )

                // Analysis Progress
                ContentViewProgress(isAnalyzing: isAnalyzing)

                // Results
                ContentViewResults(lintIssues: lintIssues, isAnalyzing: isAnalyzing)

                Spacer()
            }
            .frame(minWidth: 600, minHeight: 400)
            .navigationTitle("Project Linter")
            .sheet(isPresented: $showRuleSelector) {
                RuleSelectionDialog(
                    allPatternsByCategory: allPatternsByCategory,
                    enabledRuleNames: $enabledRuleNames,
                    onSave: saveEnabledRules
                )
            }
            .fileImporter(isPresented: $showingDirectoryPicker, allowedContentTypes: [.folder]) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let url):
                        selectedDirectory = url.path
                    case .failure(let error):
                        print("Error selecting directory: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Save enabled rules to UserDefaults
    private func saveEnabledRules() {
        if let data = try? JSONEncoder().encode(enabledRuleNames) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    /// Opens the directory picker to select a project folder
    private func selectDirectory() {
        showingDirectoryPicker = true
    }

    /// Analyzes the selected project directory
    private func analyzeProject() {
        guard !selectedDirectory.isEmpty else { return }
        runLinter(at: selectedDirectory)
    }

    /// Runs the project linter analysis at the given directory path.
    ///
    /// This function uses SwiftSyntax-based pattern detection and properly filters results
    /// based on the user's selected rules. It sets the `isAnalyzing` state to `true` and 
    /// simulates an analysis delay (2 seconds) using `DispatchQueue.main.asyncAfter`. 
    /// After the delay, it creates SwiftSyntax detectors and analyzes the project directory 
    /// specified by `path`, filtering results to only include issues from enabled rules.
    /// The results are assigned to the `lintIssues` state variable. If no real issues are found,
    /// it populates `lintIssues` with demo issues for illustrative purposes.
    /// Finally, it sets `isAnalyzing` back to `false`.
    private func runLinter(at path: String) {
        isAnalyzing = true

        // Simulate analysis delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            var allIssues: [LintIssue] = []

            // Determine which categories have enabled rules
            let enabledCategories = getEnabledCategories()

            // Only use ProjectLinter for analysis
            if !enabledCategories.isEmpty {
                let linter = ProjectLinter()
                let crossFileIssues = linter.analyzeProject(at: path, categories: enabledCategories)
                allIssues.append(contentsOf: crossFileIssues)
            }

            self.lintIssues = allIssues

            self.isAnalyzing = false
        }
    }

    /// Determines which pattern categories have enabled rules.
    ///
    /// - Returns: An array of PatternCategory values that have at least one enabled rule.
    private func getEnabledCategories() -> [PatternCategory] {
        PatternConfiguration.getEnabledCategories(
            patternRegistry: systemComponents.patternRegistry,
            enabledRuleNames: enabledRuleNames
        )
    }

    /// Filters lint issues to only include those from enabled rules using registry mapping.
    ///
    /// This function uses the registry to determine which categories are enabled based on
    /// the user's selected rule names, then filters issues to only include those from
    /// enabled categories. This ensures the UI always reflects the actual registry state.
    ///
    /// - Parameter issues: The array of all detected issues.
    /// - Returns: An array containing only issues from enabled rules.
    private func filterIssuesByEnabledRules(_ issues: [LintIssue]) -> [LintIssue] {
        PatternConfiguration.filterIssuesByEnabledRules(issues, enabledRuleNames: enabledRuleNames)
    }

    /// A static factory for testing purposes that hosts ContentView with a proper @StateObject environment.
    /// Use this in tests to avoid State warnings.
    ///
    /// Do NOT instantiate ContentView() directly outside a View hierarchy (including in tests or previews).
    /// Always use ContentViewPreviewHost to avoid @State access warnings.
    static func testHostView() -> some View {
        ContentViewPreviewHost()
    }
}

// All @State usage must occur inside a proper View hierarchy to prevent State warnings in previews/tests.
// The ContentViewPreviewHost struct below correctly hosts ContentView inside a View with @StateObject,
// ensuring no runtime warnings occur due to improper @State usage.
//
// Direct use of @State outside of a View or without a proper hierarchy will trigger runtime warnings.

// Always use ContentViewPreviewHost() for previews and tests to avoid @State
// access warnings. Never use ContentView() directly.
struct ContentViewPreviewHost: View {
    @StateObject private var systemComponents = SystemComponents()
    var body: some View {
        ContentView()
            .environmentObject(systemComponents)
            .onAppear { systemComponents.initialize() }
    }
}

#Preview {
    // Use the preview host to avoid @State warnings.
    ContentViewPreviewHost()
}

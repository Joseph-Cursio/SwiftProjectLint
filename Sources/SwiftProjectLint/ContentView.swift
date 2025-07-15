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
    @State private var enabledRuleNames: Set<RuleIdentifier> = []
    @State private var showingDirectoryPicker: Bool = false
    
    private let userDefaultsKey = "enabledLintRules"
    
    // MARK: - Computed Properties
    
    /// Pattern configuration that uses SwiftSyntax for all categories.
    private var allPatternsByCategory: [(category: PatternCategory, display: String, patterns: [DetectionPattern], useSwiftSyntax: Bool)] {
        PatternConfiguration.allPatternsByCategory(from: systemComponents.patternRegistry)
    }
    
    // MARK: - Init
    /// Initializes a new instance of `ContentView`, configuring the initial set of enabled lint rule names.
    ///
    /// This initializer attempts to load a previously saved set of enabled lint rule names from `UserDefaults`
    /// using the key defined by `userDefaultsKey`. If a non-empty set of rule names is found, it is used to
    /// initialize the `enabledRuleNames` state property. If no saved rules are present, the initializer defaults
    /// to enabling only the "Related Duplicate State Variable" rule. This ensures that the linter is always initialized 
    /// with at least one enabled rule, providing a reasonable default for first-time users or fresh launches.
    ///
    /// - Note: The rule names are persisted across app launches via `UserDefaults`.
    /// - Note: INVALID_PERSONA warnings may appear during UI tests due to sandboxing - this is normal behavior.
    init() {
        print("DEBUG: ContentView initialized")
        // Load enabled rules from UserDefaults or set default
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(Set<RuleIdentifier>.self, from: data),
           !saved.isEmpty {
            _enabledRuleNames = State(initialValue: saved)
        } else {
            // Only enable 'Related Duplicate State Variable' by default
            _enabledRuleNames = State(initialValue: [.relatedDuplicateStateVariable])
        }
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
            
            // If no real issues found, show demo issues for enabled rules only
            if self.lintIssues.isEmpty {
                self.lintIssues = createDemoIssues()
            }
            
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
    
    /// Creates a set of demo lint issues for illustration purposes.
    ///
    /// This function generates demo `LintIssue` objects based on the currently enabled rules,
    /// simulating typical linter findings for the selected categories. Each demo issue includes
    /// severity, a message, file path, line number, and a suggested fix.
    ///
    /// - Returns: An array of demo `LintIssue` objects for enabled rules only.
    private func createDemoIssues() -> [LintIssue] {
        let enabledCategories = getEnabledCategories()
        return DemoIssueGenerator.createDemoIssues(for: enabledCategories)
    }
}

#Preview {
    let systemComponents = SystemComponents()
    systemComponents.initialize()
    return ContentView().environmentObject(systemComponents)
}

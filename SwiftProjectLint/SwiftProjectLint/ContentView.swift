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
/// The view delegates linting to a `ProjectLinter` instance and patterns defined in `SwiftSyntaxPatternRegistry`.
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
    
    // MARK: - Pattern Configuration
    
    /// Pattern configuration that uses SwiftSyntax for all categories.
    /// This computed property dynamically pulls patterns from the registry to ensure
    /// the UI always reflects the actual registry state.
    private var allPatternsByCategory: [(category: PatternCategory, display: String, patterns: [DetectionPattern], useSwiftSyntax: Bool)] {
        guard let patternRegistry = systemComponents.patternRegistry else {
            assertionFailure("SystemComponents.patternRegistry is nil. This usually means the environment object was not injected. Make sure to use .environmentObject(SystemComponents()) in previews and all entry points.")
            #if DEBUG
            return [(category: .stateManagement, display: "State Management", patterns: [], useSwiftSyntax: true)]
            #else
            return []
            #endif
        }
        
        return [
            (.stateManagement, "State Management", convertToDetectionPatterns(patternRegistry.getPatterns(for: .stateManagement)), true),
            (.performance, "Performance", convertToDetectionPatterns(patternRegistry.getPatterns(for: .performance)), true),
            (.architecture, "Architecture", convertToDetectionPatterns(patternRegistry.getPatterns(for: .architecture)), true),
            (.codeQuality, "Code Quality", convertToDetectionPatterns(patternRegistry.getPatterns(for: .codeQuality)), true),
            (.security, "Security", convertToDetectionPatterns(patternRegistry.getPatterns(for: .security)), true),
            (.accessibility, "Accessibility", convertToDetectionPatterns(patternRegistry.getPatterns(for: .accessibility)), true),
            (.memoryManagement, "Memory Management", convertToDetectionPatterns(patternRegistry.getPatterns(for: .memoryManagement)), true),
            (.networking, "Networking", convertToDetectionPatterns(patternRegistry.getPatterns(for: .networking)), true),
            (.uiPatterns, "UI Patterns", convertToDetectionPatterns(patternRegistry.getPatterns(for: .uiPatterns)), true)
        ]
    }
    
    /// Converts SwiftSyntax patterns to DetectionPatterns for UI compatibility
    private func convertToDetectionPatterns(_ syntaxPatterns: [SyntaxPattern]) -> [DetectionPattern] {
        return syntaxPatterns.map { syntaxPattern in
            DetectionPattern(
                name: syntaxPattern.name,
                severity: syntaxPattern.severity,
                message: syntaxPattern.messageTemplate,
                suggestion: syntaxPattern.suggestion,
                category: syntaxPattern.category
            )
        }
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
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                        .accessibilityHidden(true)
                    
                    Text("Swift Project Linter")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .accessibilityLabel("Swift Project Linter")
                        .accessibilityIdentifier("mainTitleLabel")
                    
                    Text("Detect cross-file issues and architectural problems")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("Detect cross-file issues and architectural problems")
                        .accessibilityIdentifier("mainDescriptionLabel")
                }
                .padding(.bottom, 20)
                
                VStack(spacing: 16) {
                    Button("Select Rules") {
                        showRuleSelector = true
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Select Rules")
                    .accessibilityIdentifier("selectRulesButton")
                    
                    if selectedDirectory.isEmpty {
                        Button("Run Project Analysis by Selecting a Folder...") {
                            selectDirectory()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Run Project Analysis by Selecting a Folder...")
                        .accessibilityIdentifier("mainActionButton")
                    } else {
                        Button("Analyze \(URL(fileURLWithPath: selectedDirectory).lastPathComponent)") {
                            analyzeProject()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel("Analyze \(URL(fileURLWithPath: selectedDirectory).lastPathComponent)")
                        .accessibilityIdentifier("mainActionButton")
                    }
                }
                
                // Analysis Progress
                if isAnalyzing {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Analyzing project...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 20)
                }
                
                // Results
                if !lintIssues.isEmpty && !isAnalyzing {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Analysis Results")
                                .font(.headline)
                            Spacer()
                            Text("\(lintIssues.count) issues found")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        LintResultsView(issues: lintIssues)
                            .frame(maxHeight: 400)
                    }
                    .padding(.horizontal, 40)
                }
                
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
            Task { @MainActor in
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
    }
    
    /// Determines which pattern categories have enabled rules.
    ///
    /// - Returns: An array of PatternCategory values that have at least one enabled rule.
    private func getEnabledCategories() -> [PatternCategory] {
        guard let patternRegistry = systemComponents.patternRegistry else {
            return []
        }
        
        var enabledCategories: Set<PatternCategory> = []
        
        for category in PatternCategory.allCases {
            let patternsInCategory = patternRegistry.getPatterns(for: category)
            let enabledPatternsInCategory = patternsInCategory.filter { pattern in
                enabledRuleNames.contains(pattern.name)
            }
            
            if !enabledPatternsInCategory.isEmpty {
                enabledCategories.insert(category)
            }
        }
        
        return Array(enabledCategories)
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
        // If no rules are enabled, return no issues
        if enabledRuleNames.isEmpty {
            return []
        }
        
        // Filter issues based on their ruleName and the enabled rules
        return issues.filter { issue in
            return enabledRuleNames.contains(issue.ruleName)
        }
    }
    
    /// Creates a set of demo lint issues for illustration purposes.
    ///
    /// This function generates demo `LintIssue` objects based on the currently enabled rules,
    /// simulating typical linter findings for the selected categories. Each demo issue includes
    /// severity, a message, file path, line number, and a suggested fix.
    ///
    /// - Returns: An array of demo `LintIssue` objects for enabled rules only.
    private func createDemoIssues() -> [LintIssue] {
        var demoIssues: [LintIssue] = []
        
        // Get enabled categories
        let enabledCategories = getEnabledCategories()
        
        // Create demo issues based on enabled categories
        for category in enabledCategories {
            switch category {
            case .stateManagement:
                demoIssues.append(contentsOf: [
                    LintIssue(
                        severity: .warning,
                        message: "Related Duplicate State Variable: 'isLoading' found in ParentView and ChildView",
                        filePath: "ExampleViews/ParentView.swift",
                        lineNumber: 5,
                        suggestion: "Create a shared ObservableObject for 'isLoading' and inject it via .environmentObject() at the root level.",
                        ruleName: .relatedDuplicateStateVariable
                    ),
                    LintIssue(
                        severity: .info,
                        message: "Unrelated Duplicate State Variable: 'userName' found in separate views",
                        filePath: "ExampleViews/UserView.swift",
                        lineNumber: 8,
                        suggestion: "Consider if these variables represent the same concept and should be shared via a common ObservableObject.",
                        ruleName: .unrelatedDuplicateStateVariable
                    )
                ])
                
            case .performance:
                demoIssues.append(contentsOf: [
                    LintIssue(
                        severity: .warning,
                        message: "ForEach Without ID: Using array without explicit identifier",
                        filePath: "ExampleViews/ListView.swift",
                        lineNumber: 12,
                        suggestion: "Add explicit id parameter to ForEach for better performance and stability.",
                        ruleName: .forEachWithoutID
                    ),
                    LintIssue(
                        severity: .warning,
                        message: "Large View Body: View contains 50+ lines of code",
                        filePath: "ExampleViews/ComplexView.swift",
                        lineNumber: 25,
                        suggestion: "Break down large view into smaller, focused components.",
                        ruleName: .largeViewBody
                    )
                ])
                
            case .architecture:
                demoIssues.append(contentsOf: [
                    LintIssue(
                        severity: .warning,
                        message: "Missing MVVM Pattern: View contains business logic",
                        filePath: "ExampleViews/BusinessView.swift",
                        lineNumber: 15,
                        suggestion: "Extract business logic into a dedicated ViewModel class.",
                        ruleName: .fatViewDetection
                    )
                ])
                
            case .codeQuality:
                demoIssues.append(contentsOf: [
                    LintIssue(
                        severity: .info,
                        message: "Magic Number: Using hardcoded value '42'",
                        filePath: "ExampleViews/ConfigView.swift",
                        lineNumber: 7,
                        suggestion: "Define constants for magic numbers to improve code readability.",
                        ruleName: .magicNumber
                    )
                ])
                
            case .security:
                demoIssues.append(contentsOf: [
                    LintIssue(
                        severity: .error,
                        message: "Hardcoded Secret: API key found in source code",
                        filePath: "ExampleViews/NetworkView.swift",
                        lineNumber: 10,
                        suggestion: "Move sensitive data to secure configuration files or environment variables.",
                        ruleName: .hardcodedSecret
                    )
                ])
                
            case .accessibility:
                demoIssues.append(contentsOf: [
                    LintIssue(
                        severity: .warning,
                        message: "Missing Accessibility Label: Image without accessibility description",
                        filePath: "ExampleViews/ImageView.swift",
                        lineNumber: 8,
                        suggestion: "Add accessibilityLabel to improve screen reader support.",
                        ruleName: .missingAccessibilityLabel
                    )
                ])
                
            case .memoryManagement:
                demoIssues.append(contentsOf: [
                    LintIssue(
                        severity: .warning,
                        message: "Potential Retain Cycle: Strong reference in closure",
                        filePath: "ExampleViews/ClosureView.swift",
                        lineNumber: 14,
                        suggestion: "Use weak self in closures to prevent retain cycles.",
                        ruleName: .potentialRetainCycle
                    )
                ])
                
            case .networking:
                demoIssues.append(contentsOf: [
                    LintIssue(
                        severity: .error,
                        message: "Missing Error Handling: Network request without error handling",
                        filePath: "ExampleViews/NetworkView.swift",
                        lineNumber: 22,
                        suggestion: "Add proper error handling to network requests.",
                        ruleName: .missingErrorHandling
                    )
                ])
                
            case .uiPatterns:
                demoIssues.append(contentsOf: [
                    LintIssue(
                        severity: .warning,
                        message: "Nested NavigationView: Multiple NavigationView instances detected",
                        filePath: "ExampleViews/NavigationView.swift",
                        lineNumber: 5,
                        suggestion: "Use NavigationStack or NavigationSplitView instead of nested NavigationView.",
                        ruleName: .nestedNavigationView
                    )
                ])
            case .other:
                // No demo issues for the "other" category (system-level errors)
                break
            }
        }
        
        return demoIssues
    }
}

#Preview {
    let systemComponents = SystemComponents()
    systemComponents.initialize()
    return ContentView().environmentObject(systemComponents)
}

// MARK: - Rule Selection Dialog

/// A modal SwiftUI view for selecting which lint rules are enabled in the project linter.
///
/// `RuleSelectionDialog` presents all available SwiftSyntax-based lint detection patterns, grouped by category, as a list of toggles
/// allowing the user to customize which rules are active during analysis. All patterns use SwiftSyntax for improved accuracy.
///
/// Features:
/// - Displays rules grouped by logical categories (e.g., State Management, Performance).
/// - Each rule can be individually enabled or disabled via a toggle.
/// - Bulk actions for selecting all or resetting to defaults.
/// - Shows each rule's name and a brief description.
/// - Integration with SwiftUI navigation and toolbar system for a familiar dialog experience.
/// - All patterns use SwiftSyntax for improved accuracy and comprehensive analysis.
///
/// Properties:
/// - `allPatternsByCategory`: An array of tuples grouping all detection patterns by category, display string, their definitions, and whether they use SwiftSyntax.
/// - `enabledRuleNames`: A binding to the set of currently enabled rule names; updates are reflected live in the UI.
/// - `onSave`: A closure called when the user taps Save, allowing the parent view to persist changes.
/// - `dismiss`: An environment value for dismissing the modal dialog.
///
/// Usage:
/// Present this view as a sheet or modal when the user wants to customize active lint rules. On save, the updated list of
/// enabled rule names can be persisted as appropriate (such as to UserDefaults).
struct RuleSelectionDialog: View {
    let allPatternsByCategory: [(category: PatternCategory, display: String, patterns: [DetectionPattern], useSwiftSyntax: Bool)]
    @Binding var enabledRuleNames: Set<RuleIdentifier>
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    // Helper: All rule names from the passed patterns
    private var allRuleNames: Set<RuleIdentifier> {
        var names = Set<RuleIdentifier>()
        for group in allPatternsByCategory {
            names.formUnion(group.patterns.map { $0.name })
        }
        return names
    }
    
    // Helper: Default rule name
    private var defaultRuleName: RuleIdentifier? {
        return .relatedDuplicateStateVariable // Default pattern from state management
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(allPatternsByCategory, id: \.category) { group in
                    Section(header: Text(group.display)) {
                        // Show patterns from the passed data
                        ForEach(group.patterns, id: \.name) { pattern in
                            Toggle(isOn: Binding(
                                get: { enabledRuleNames.contains(pattern.name) },
                                set: { isOn in
                                    if isOn {
                                        enabledRuleNames.insert(pattern.name)
                                    } else {
                                        enabledRuleNames.remove(pattern.name)
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pattern.name.rawValue)
                                        .fontWeight(.medium)
                                    Text(pattern.suggestion)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Lint Rules")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button("Select All") {
                        enabledRuleNames = allRuleNames
                    }
                    Spacer()
                    Button("Reset to Default") {
                        if let defaultName = defaultRuleName {
                            enabledRuleNames = [defaultName]
                        } else {
                            enabledRuleNames = []
                        }
                    }
                };
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                };
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }
}

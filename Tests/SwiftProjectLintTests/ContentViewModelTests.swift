import Testing
import SwiftUI
import SwiftProjectLintCore

@testable import SwiftProjectLint

@Suite("ContentViewModel Tests")
@MainActor
struct ContentViewModelTests {

    // MARK: - Initial State

    @Test("initial state has empty selected directory")
    func initialSelectedDirectoryIsEmpty() {
        let viewModel = ContentViewModel()
        #expect(viewModel.selectedDirectory.isEmpty)
    }

    @Test("initial state is not analyzing")
    func initialIsAnalyzingIsFalse() {
        let viewModel = ContentViewModel()
        #expect(!viewModel.isAnalyzing)
    }

    @Test("initial state has no lint issues")
    func initialLintIssuesIsEmpty() {
        let viewModel = ContentViewModel()
        #expect(viewModel.lintIssues.isEmpty)
    }

    @Test("initial state has rule selector hidden")
    func initialShowRuleSelectorIsFalse() {
        let viewModel = ContentViewModel()
        #expect(!viewModel.showRuleSelector)
    }

    @Test("initial state has directory picker hidden")
    func initialShowingDirectoryPickerIsFalse() {
        let viewModel = ContentViewModel()
        #expect(!viewModel.showingDirectoryPicker)
    }

    @Test("initial state has no analysis task")
    func initialAnalysisTaskIsNil() {
        let viewModel = ContentViewModel()
        #expect(viewModel.analysisTask == nil)
    }

    @Test("initial enabled rules defaults to relatedDuplicateStateVariable")
    func initialEnabledRulesDefault() {
        // Clear any saved rules to test default
        UserDefaults.standard.removeObject(forKey: "enabledLintRules")
        let viewModel = ContentViewModel()
        #expect(viewModel.enabledRuleNames.contains(.relatedDuplicateStateVariable))
    }

    // MARK: - selectDirectory

    @Test("selectDirectory sets showingDirectoryPicker to true")
    func selectDirectorySetsShowingPicker() {
        let viewModel = ContentViewModel()
        viewModel.selectDirectory()
        #expect(viewModel.showingDirectoryPicker)
    }

    // MARK: - analyzeProject

    @Test("analyzeProject guards when directory is empty")
    func analyzeProjectGuardsEmptyDirectory() {
        let viewModel = ContentViewModel()
        viewModel.analyzeProject()
        #expect(!viewModel.isAnalyzing)
    }

    // MARK: - cancelAnalysis

    @Test("cancelAnalysis cancels the task")
    func cancelAnalysisCancelsTask() {
        let viewModel = ContentViewModel()
        viewModel.analysisTask = Task { }
        viewModel.cancelAnalysis()
        #expect(viewModel.analysisTask?.isCancelled == true)
    }

    // MARK: - saveEnabledRules / UserDefaults round-trip

    @Test("saveEnabledRules persists to UserDefaults and loads back")
    func saveAndLoadEnabledRules() throws {
        let viewModel = ContentViewModel()
        let testRules: Set<RuleIdentifier> = [.missingStateObject, .fatView]
        viewModel.enabledRuleNames = testRules
        viewModel.saveEnabledRules()

        // Read back from UserDefaults
        let data = try #require(UserDefaults.standard.data(forKey: "enabledLintRules"))
        let loaded = try JSONDecoder().decode(Set<RuleIdentifier>.self, from: data)
        #expect(loaded == testRules)

        // Clean up
        UserDefaults.standard.removeObject(forKey: "enabledLintRules")
    }

    // MARK: - getEnabledCategories

    @Test("getEnabledCategories returns empty when registry is nil")
    func getEnabledCategoriesWithNilRegistry() {
        let viewModel = ContentViewModel()
        viewModel.patternRegistry = nil
        let categories = viewModel.getEnabledCategories()
        #expect(categories.isEmpty)
    }

    @Test("getEnabledCategories returns categories with configured registry")
    func getEnabledCategoriesWithRegistry() {
        let systemComponents = SystemComponents()
        systemComponents.initialize()
        let viewModel = ContentViewModel()
        viewModel.patternRegistry = systemComponents.patternRegistry
        viewModel.enabledRuleNames = [.relatedDuplicateStateVariable]
        let categories = viewModel.getEnabledCategories()
        #expect(!categories.isEmpty)
        #expect(categories.contains(.stateManagement))
    }

    // MARK: - filterIssuesByEnabledRules

    @Test("filterIssuesByEnabledRules returns empty when no rules enabled")
    func filterWithNoRulesEnabled() {
        let viewModel = ContentViewModel()
        viewModel.enabledRuleNames = []
        let issues = [
            LintIssue(
                severity: .warning, message: "Test", filePath: "/test.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            )
        ]
        let filtered = viewModel.filterIssuesByEnabledRules(issues)
        #expect(filtered.isEmpty)
    }

    @Test("filterIssuesByEnabledRules keeps only matching rules")
    func filterKeepsMatchingRules() {
        let viewModel = ContentViewModel()
        viewModel.enabledRuleNames = [.missingStateObject]
        let issues = [
            LintIssue(
                severity: .warning, message: "State issue", filePath: "/test.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .error, message: "Missing @StateObject", filePath: "/test.swift",
                lineNumber: 5, suggestion: nil, ruleName: .missingStateObject
            )
        ]
        let filtered = viewModel.filterIssuesByEnabledRules(issues)
        #expect(filtered.count == 1)
        #expect(filtered[0].ruleName == .missingStateObject)
    }

    // MARK: - allPatternsByCategory

    @Test("allPatternsByCategory returns empty when registry is nil")
    func allPatternsByCategoryNilRegistry() {
        let viewModel = ContentViewModel()
        viewModel.patternRegistry = nil
        #expect(viewModel.allPatternsByCategory.isEmpty)
    }

    @Test("allPatternsByCategory returns categories with configured registry")
    func allPatternsByCategoryWithRegistry() {
        let systemComponents = SystemComponents()
        systemComponents.initialize()
        let viewModel = ContentViewModel()
        viewModel.patternRegistry = systemComponents.patternRegistry
        let patterns = viewModel.allPatternsByCategory
        #expect(!patterns.isEmpty)
    }
}

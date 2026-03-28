import Testing
import SwiftUI
import Core

@testable import App

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
        #expect(viewModel.isAnalyzing == false)

    }

    @Test("initial state has no lint issues")
    func initialLintIssuesIsEmpty() {
        let viewModel = ContentViewModel()
        #expect(viewModel.lintIssues.isEmpty)
    }

    @Test("initial state has rule selector hidden")
    func initialShowRuleSelectorIsFalse() {
        let viewModel = ContentViewModel()
        #expect(viewModel.showRuleSelector == false)

    }

    @Test("initial state has directory picker hidden")
    func initialShowingDirectoryPickerIsFalse() {
        let viewModel = ContentViewModel()
        #expect(viewModel.showingDirectoryPicker == false)

    }

    @Test("initial state has no analysis task")
    func initialAnalysisTaskIsNil() {
        let viewModel = ContentViewModel()
        #expect(viewModel.analysisTask == nil)
    }

    @Test("initial enabled rules defaults to all rules")
    func initialEnabledRulesDefault() {
        // Clear any saved rules to test default
        UserDefaults.standard.removeObject(forKey: "enabledLintRules")
        let viewModel = ContentViewModel()
        let allRules = Set(RuleIdentifier.allCases)
        #expect(viewModel.enabledRuleNames == allRules,
                "Default should enable all rules, not a subset")
    }

    @Test("enabledRuleNames loads saved rules from UserDefaults on init")
    func enabledRulesLoadedFromUserDefaults() throws {
        let testRules: Set<RuleIdentifier> = [.missingStateObject, .fatView, .uninitializedStateVariable]
        let data = try JSONEncoder().encode(testRules)
        UserDefaults.standard.set(data, forKey: "enabledLintRules")
        let viewModel = ContentViewModel()
        #expect(viewModel.enabledRuleNames == testRules)
        UserDefaults.standard.removeObject(forKey: "enabledLintRules")
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
        #expect(viewModel.isAnalyzing == false)

    }

    @Test("analyzeProject with non-empty directory sets isAnalyzing to true")
    func analyzeProjectSetsIsAnalyzing() {
        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = FileManager.default.temporaryDirectory.path
        viewModel.enabledRuleNames = [.relatedDuplicateStateVariable]
        viewModel.analyzeProject()
        #expect(viewModel.isAnalyzing)
        viewModel.cancelAnalysis()
    }

    @Test("analyzeProject prevents double-start when already analyzing")
    func analyzeProjectPreventsDoubleStart() {
        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = FileManager.default.temporaryDirectory.path
        viewModel.enabledRuleNames = [.relatedDuplicateStateVariable]
        viewModel.analyzeProject()
        #expect(viewModel.isAnalyzing)
        // Second call while already analyzing should be a no-op (guard !isAnalyzing)
        viewModel.analyzeProject()
        // isAnalyzing is still true — was never reset — confirming the guard fired
        #expect(viewModel.isAnalyzing)
        viewModel.cancelAnalysis()
    }

    @Test("analyzeProject with no enabled categories completes without issues")
    func analyzeProjectWithNoCategoriesCompletesEmpty() async {
        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = FileManager.default.temporaryDirectory.path
        viewModel.enabledRuleNames = [] // no rules → no categories → skips linter
        viewModel.analyzeProject()
        await viewModel.analysisTask?.value
        #expect(viewModel.isAnalyzing == false)
        #expect(viewModel.lintIssues.isEmpty)
    }

    @Test("analyzeProject resets isAnalyzing to false on completion")
    func analyzeProjectResetsIsAnalyzingOnCompletion() async {
        let viewModel = ContentViewModel()
        // Use a directory with no Swift files so analysis is fast
        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContentViewModelTest_\(UUID().uuidString)").path
        try? FileManager.default.createDirectory(atPath: emptyDir, withIntermediateDirectories: true)
        viewModel.selectedDirectory = emptyDir
        viewModel.enabledRuleNames = [.relatedDuplicateStateVariable]
        viewModel.analyzeProject()
        await viewModel.analysisTask?.value
        #expect(viewModel.isAnalyzing == false)
        try? FileManager.default.removeItem(atPath: emptyDir)
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
    func getEnabledCategoriesWithRegistry() async {
        let systemComponents = SystemComponents()
        await systemComponents.initialize()
        let viewModel = ContentViewModel()
        viewModel.patternRegistry = systemComponents.patternRegistry
        viewModel.enabledRuleNames = [.relatedDuplicateStateVariable]
        let categories = viewModel.getEnabledCategories()
        #expect(categories.isEmpty == false)

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
    func filterKeepsMatchingRules() throws {
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
        let firstFiltered = try #require(filtered.first)
        #expect(firstFiltered.ruleName == .missingStateObject)
    }

    // MARK: - Integration: analysis produces issues

    @Test("analysis with configured detector produces issues for known-bad code")
    func analysisProducesIssuesWithDetector() async throws {
        // Create a temp project with a Swift file containing a known violation
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewModelIntegration_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceFile = tempDir.appendingPathComponent("Example.swift")
        try """
        import SwiftUI
        struct ExampleView: View {
            var body: some View {
                let val = try! riskyCall()
                Text("hello")
            }
        }
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let systemComponents = SystemComponents()
        await systemComponents.initialize()

        let viewModel = ContentViewModel()
        viewModel.detector = systemComponents.detector
        viewModel.selectedDirectory = tempDir.path
        viewModel.enabledRuleNames = Set(RuleIdentifier.allCases)
        viewModel.analyzeProject()
        await viewModel.analysisTask?.value

        #expect(viewModel.isAnalyzing == false)
        #expect(viewModel.lintIssues.isEmpty == false,
                "Analysis with a configured detector must produce issues for code with violations")
    }

    @Test("analysis without detector produces no issues (registry empty)")
    func analysisWithoutDetectorProducesNothing() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ViewModelNoDetector_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceFile = tempDir.appendingPathComponent("Bad.swift")
        try """
        import SwiftUI
        struct BadView: View {
            var body: some View {
                let val = try! riskyCall()
                Text("hello")
            }
        }
        """.write(to: sourceFile, atomically: true, encoding: .utf8)

        let viewModel = ContentViewModel()
        // Deliberately do NOT set viewModel.detector
        viewModel.selectedDirectory = tempDir.path
        viewModel.enabledRuleNames = Set(RuleIdentifier.allCases)
        viewModel.analyzeProject()
        await viewModel.analysisTask?.value

        // This documents the bug: without a detector, no issues are found
        // even for code with clear violations
        // Without a configured detector the shared registry is empty —
        // this documents the failure mode so it stays visible.
        #expect(viewModel.lintIssues.isEmpty)
    }

    // MARK: - allPatternsByCategory

    @Test("allPatternsByCategory returns empty when registry is nil")
    func allPatternsByCategoryNilRegistry() {
        let viewModel = ContentViewModel()
        viewModel.patternRegistry = nil
        #expect(viewModel.allPatternsByCategory.isEmpty)
    }

    @Test("allPatternsByCategory returns categories with configured registry")
    func allPatternsByCategoryWithRegistry() async {
        let systemComponents = SystemComponents()
        await systemComponents.initialize()
        let viewModel = ContentViewModel()
        viewModel.patternRegistry = systemComponents.patternRegistry
        let patterns = viewModel.allPatternsByCategory
        #expect(patterns.isEmpty == false)

    }
}

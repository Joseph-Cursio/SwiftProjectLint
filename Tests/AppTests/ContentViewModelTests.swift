@testable import App
import Foundation
import SwiftProjectLintModels
import Testing

// MARK: - Additional ContentViewModel Tests

@Suite("ContentViewModel Pattern Tests")
@MainActor
struct ContentViewModelPatternTests {
    /// The saved rules' store: never `.standard`, which other test processes share (`IsolatedDefaults`).
    private let store = IsolatedDefaults()

    // MARK: - allPatternsByCategory

    @Test("allPatternsByCategory returns empty when registry is nil")
    func allPatternsByCategoryNilRegistry() {
        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.patternRegistry = nil
        #expect(viewModel.allPatternsByCategory.isEmpty)
    }

    @Test("allPatternsByCategory returns categories with configured registry")
    func allPatternsByCategoryWithRegistry() async {
        let systemComponents = SystemComponents()
        await systemComponents.initialize()
        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.patternRegistry = systemComponents.patternRegistry
        let patterns = viewModel.allPatternsByCategory
        #expect(patterns.isEmpty == false)
    }
}

@Suite("ContentViewModel Tests")
@MainActor
struct ContentViewModelTests {
    /// The saved rules' store: never `.standard`, which other test processes share (`IsolatedDefaults`).
    private let store = IsolatedDefaults()

    /// A unique, empty directory for a test to analyze.
    ///
    /// Never point the linter at `FileManager.default.temporaryDirectory` *itself*.
    /// That is shared machine state, and on a developer machine it accumulates Swift
    /// sources — 26,000+ of them after a day of builds, largely from the toolchain's
    /// own `swift-generated-sources`. Analysing it parses every one through
    /// SwiftSyntax, which made this suite non-hermetic: fast on a clean machine,
    /// stalled for ten minutes on a working one, and the single reason a full
    /// `swift test` run appeared to hang.
    ///
    /// The caller is responsible for removing the directory; `defer` is the tidiest
    /// way to do that.
    private func makeIsolatedDirectory(_ name: String = #function) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContentViewModelTests_\(name)_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.path
    }

    // MARK: - Initial State

    @Test("initial state has empty selected directory")
    func initialSelectedDirectoryIsEmpty() {
        let viewModel = ContentViewModel(defaults: store.defaults)
        #expect(viewModel.selectedDirectory.isEmpty)
    }

    @Test("initial state is not analyzing")
    func initialIsAnalyzingIsFalse() {
        let viewModel = ContentViewModel(defaults: store.defaults)
        #expect(viewModel.isAnalyzing == false)
    }

    @Test("initial state has no lint issues")
    func initialLintIssuesIsEmpty() {
        let viewModel = ContentViewModel(defaults: store.defaults)
        #expect(viewModel.lintIssues.isEmpty)
    }

    @Test("initial state has rule selector hidden")
    func initialShowRuleSelectorIsFalse() {
        let viewModel = ContentViewModel(defaults: store.defaults)
        #expect(viewModel.showRuleSelector == false)
    }

    @Test("initial state has directory picker hidden")
    func initialShowingDirectoryPickerIsFalse() {
        let viewModel = ContentViewModel(defaults: store.defaults)
        #expect(viewModel.showingDirectoryPicker == false)
    }

    @Test("initial state has no analysis task")
    func initialAnalysisTaskIsNil() {
        let viewModel = ContentViewModel(defaults: store.defaults)
        #expect(viewModel.analysisTask == nil)
    }

    @Test("initial enabled rules defaults to all rules")
    func initialEnabledRulesDefault() {
        // Clear any saved rules to test default
        store.defaults.removeObject(forKey: ContentViewModel.enabledRulesKey)
        let viewModel = ContentViewModel(defaults: store.defaults)
        let allRules = Set(RuleIdentifier.allCases)
        #expect(viewModel.enabledRuleNames == allRules,
                "Default should enable all rules, not a subset")
    }

    @Test("enabledRuleNames loads saved rules from UserDefaults on init")
    func enabledRulesLoadedFromUserDefaults() throws {
        let testRules: Set<RuleIdentifier> = [.missingStateObject, .fatView, .uninitializedStateVariable]
        let data = try JSONEncoder().encode(testRules)
        store.defaults.set(data, forKey: ContentViewModel.enabledRulesKey)
        let viewModel = ContentViewModel(defaults: store.defaults)
        #expect(viewModel.enabledRuleNames == testRules)
        store.defaults.removeObject(forKey: ContentViewModel.enabledRulesKey)
    }

    // MARK: - selectDirectory

    @Test("selectDirectory sets showingDirectoryPicker to true")
    func selectDirectorySetsShowingPicker() {
        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.selectDirectory()
        #expect(viewModel.showingDirectoryPicker)
    }

    // MARK: - analyzeProject

    @Test("analyzeProject guards when directory is empty")
    func analyzeProjectGuardsEmptyDirectory() {
        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.analyzeProject()
        #expect(viewModel.isAnalyzing == false)
    }

    @Test("analyzeProject with non-empty directory sets isAnalyzing to true")
    func analyzeProjectSetsIsAnalyzing() throws {
        let directory = try makeIsolatedDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.selectedDirectory = directory
        viewModel.enabledRuleNames = [.relatedDuplicateStateVariable]
        viewModel.analyzeProject()
        // Safe to read synchronously: analyzeProject sets the flag before starting its
        // task, and resetting it requires the MainActor this test is holding.
        #expect(viewModel.isAnalyzing)
        viewModel.cancelAnalysis()
    }

    @Test("analyzeProject prevents double-start when already analyzing")
    func analyzeProjectPreventsDoubleStart() throws {
        let directory = try makeIsolatedDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.selectedDirectory = directory
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
    func analyzeProjectWithNoCategoriesCompletesEmpty() async throws {
        let directory = try makeIsolatedDirectory()
        defer { try? FileManager.default.removeItem(atPath: directory) }

        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.selectedDirectory = directory
        viewModel.enabledRuleNames = [] // no rules → no categories → skips linter
        viewModel.analyzeProject()
        await viewModel.analysisTask?.value
        #expect(viewModel.isAnalyzing == false)
        #expect(viewModel.lintIssues.isEmpty)
    }

    @Test("analyzeProject resets isAnalyzing to false on completion")
    func analyzeProjectResetsIsAnalyzingOnCompletion() async {
        let viewModel = ContentViewModel(defaults: store.defaults)
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
        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.analysisTask = Task { }
        viewModel.cancelAnalysis()
        #expect(viewModel.analysisTask?.isCancelled == true)
    }

    // MARK: - saveEnabledRules / UserDefaults round-trip

    @Test("saveEnabledRules persists to UserDefaults and loads back")
    func saveAndLoadEnabledRules() throws {
        let viewModel = ContentViewModel(defaults: store.defaults)
        let testRules: Set<RuleIdentifier> = [.missingStateObject, .fatView]
        viewModel.enabledRuleNames = testRules
        viewModel.saveEnabledRules()

        // Read back from UserDefaults
        let data = try #require(store.defaults.data(forKey: ContentViewModel.enabledRulesKey))
        let loaded = try JSONDecoder().decode(Set<RuleIdentifier>.self, from: data)
        #expect(loaded == testRules)

        // Clean up
        store.defaults.removeObject(forKey: ContentViewModel.enabledRulesKey)
    }

    // MARK: - getEnabledCategories

    @Test("getEnabledCategories returns empty when registry is nil")
    func getEnabledCategoriesWithNilRegistry() {
        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.patternRegistry = nil
        let categories = viewModel.getEnabledCategories()
        #expect(categories.isEmpty)
    }

    @Test("getEnabledCategories returns categories with configured registry")
    func getEnabledCategoriesWithRegistry() async {
        let systemComponents = SystemComponents()
        await systemComponents.initialize()
        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.patternRegistry = systemComponents.patternRegistry
        viewModel.enabledRuleNames = [.relatedDuplicateStateVariable]
        let categories = viewModel.getEnabledCategories()
        #expect(categories.isEmpty == false)

        #expect(categories.contains(.stateManagement))
    }

    // MARK: - filterIssuesByEnabledRules

    @Test("filterIssuesByEnabledRules returns empty when no rules enabled")
    func filterWithNoRulesEnabled() {
        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.enabledRuleNames = []
        let issues = [
            LintIssue(
                severity: .warning, message: "Test", filePath: "/test.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
        ]
        let filtered = viewModel.filterIssuesByEnabledRules(issues)
        #expect(filtered.isEmpty)
    }

    @Test("filterIssuesByEnabledRules keeps only matching rules")
    func filterKeepsMatchingRules() throws {
        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.enabledRuleNames = [.missingStateObject]
        let issues = [
            LintIssue(
                severity: .warning, message: "State issue", filePath: "/test.swift",
                lineNumber: 1, suggestion: nil, ruleName: .relatedDuplicateStateVariable
            ),
            LintIssue(
                severity: .error, message: "Missing @StateObject", filePath: "/test.swift",
                lineNumber: 5, suggestion: nil, ruleName: .missingStateObject
            ),
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

        let viewModel = ContentViewModel(defaults: store.defaults)
        viewModel.detector = systemComponents.detector
        viewModel.selectedDirectory = tempDir.path
        viewModel.enabledRuleNames = Set(RuleIdentifier.allCases)
        viewModel.analyzeProject()
        await viewModel.analysisTask?.value

        #expect(viewModel.isAnalyzing == false)
        #expect(viewModel.lintIssues.isEmpty == false,
                "Analysis with a configured detector must produce issues for code with violations")
    }

    @Test("analysis without a detector still runs the built-in rules")
    func analysisWithoutDetectorRunsBuiltInRules() async throws {
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

        let viewModel = ContentViewModel(defaults: store.defaults)
        // Deliberately do NOT set viewModel.detector
        viewModel.selectedDirectory = tempDir.path
        viewModel.enabledRuleNames = Set(RuleIdentifier.allCases)
        viewModel.analyzeProject()
        await viewModel.analysisTask?.value

        // Without a detector the linter used to read the shared registry, which
        // nothing fills, and found nothing even here. It now registers every
        // built-in rule itself, as the CLI does.
        #expect(viewModel.lintIssues.contains { $0.ruleName == .forceTry })
    }
}

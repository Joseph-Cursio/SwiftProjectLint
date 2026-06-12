import Core
import SwiftUI
import Testing

@testable import App

// MARK: - Mock Analyzer & Configuration Tests

@Suite("ContentViewModel Configuration Tests")
@MainActor
struct ContentViewModelConfigTests {

    @Test("analysis with mock analyzer returns mock issues without filesystem")
    func analysisWithMockAnalyzer() async {
        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = "/fake/path"
        viewModel.analyzer = MockProjectAnalyzer(issues: [
            LintIssue(
                severity: .warning,
                message: "Mock issue",
                filePath: "Mock.swift",
                lineNumber: 1,
                suggestion: nil,
                ruleName: .forceTry
            )
        ])
        viewModel.analyzeProject()
        await viewModel.analysisTask?.value

        #expect(viewModel.lintIssues.count == 1)
        #expect(viewModel.lintIssues.first?.message == "Mock issue")
        #expect(viewModel.isAnalyzing == false)
    }

    @Test("analysis with mock analyzer returning empty issues works")
    func analysisWithEmptyMockAnalyzer() async {
        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = "/fake/path"
        viewModel.analyzer = MockProjectAnalyzer(issues: [])
        viewModel.analyzeProject()
        await viewModel.analysisTask?.value

        #expect(viewModel.lintIssues.isEmpty)
        #expect(viewModel.isAnalyzing == false)
    }

    // MARK: - loadConfigFromProject

    @Test("loadConfigFromProject guards when directory is empty")
    func loadConfigGuardsEmptyDirectory() {
        let viewModel = ContentViewModel()
        viewModel.loadConfigFromProject()
        #expect(viewModel.ruleExclusions.isEmpty)
        #expect(viewModel.configIsDirty == false)
    }

    @Test("loadConfigFromProject loads YAML config and populates exclusions")
    func loadConfigPopulatesExclusions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoadConfig_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let yamlContent = """
        rules:
          Force Try:
            excluded_paths:
              - "Tests/"
          Magic Number:
            excluded_paths:
              - "**/*View.swift"
        """
        let configPath = tempDir.appendingPathComponent(".swiftprojectlint.yml")
        try yamlContent.write(to: configPath, atomically: true, encoding: .utf8)

        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = tempDir.path
        viewModel.loadConfigFromProject()

        #expect(viewModel.ruleExclusions[.forceTry]?.excludeTests == true)
        #expect(viewModel.ruleExclusions[.magicNumber]?.excludeViews == true)
        #expect(viewModel.configIsDirty == false)
    }

    @Test("loadConfigFromProject with no YAML file produces empty exclusions")
    func loadConfigNoYamlFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NoConfig_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = tempDir.path
        viewModel.loadConfigFromProject()
        #expect(viewModel.ruleExclusions.isEmpty)
    }

    // MARK: - saveConfigToProject

    @Test("saveConfigToProject guards when directory is empty")
    func saveConfigGuardsEmptyDirectory() {
        let viewModel = ContentViewModel()
        viewModel.saveConfigToProject()
        // Should not crash; no file written
    }

    @Test("saveConfigToProject writes YAML and clears dirty flag")
    func saveConfigWritesYaml() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveConfig_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = tempDir.path
        viewModel.ruleExclusions = [
            .forceTry: RuleExclusions(excludeTests: true, excludeViews: false)
        ]
        viewModel.configIsDirty = true
        viewModel.saveConfigToProject()

        let configPath = tempDir.appendingPathComponent(".swiftprojectlint.yml")
        #expect(FileManager.default.fileExists(atPath: configPath.path))
        #expect(viewModel.configIsDirty == false)
        #expect(viewModel.configSaveError == nil)
    }

    @Test("saveConfigToProject surfaces an error and keeps dirty when the write fails")
    func saveConfigSurfacesWriteFailure() {
        // A directory that does not exist — SafeFileWriter does not create
        // intermediate directories, so the write throws.
        let missingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Missing_\(UUID().uuidString)")
            .appendingPathComponent("nested")

        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = missingDir.path
        viewModel.ruleExclusions = [
            .forceTry: RuleExclusions(excludeTests: true, excludeViews: false)
        ]
        viewModel.configIsDirty = true
        viewModel.saveConfigToProject()

        // The failure must be surfaced, not swallowed, and the unsaved state kept.
        #expect(viewModel.configSaveError != nil)
        #expect(viewModel.configIsDirty == true)
    }

    // MARK: - updateDirtyState

    @Test("updateDirtyState is clean when no config loaded and no exclusions")
    func updateDirtyStateCleanNoConfig() {
        let viewModel = ContentViewModel()
        viewModel.updateDirtyState()
        #expect(viewModel.configIsDirty == false)
    }

    @Test("updateDirtyState is dirty when exclusions set without loaded config")
    func updateDirtyStateDirtyWithExclusions() {
        let viewModel = ContentViewModel()
        viewModel.ruleExclusions = [
            .forceTry: RuleExclusions(excludeTests: true, excludeViews: false)
        ]
        viewModel.updateDirtyState()
        #expect(viewModel.configIsDirty)
    }

    @Test("updateDirtyState is clean when state matches loaded config")
    func updateDirtyStateCleanMatchingConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirtyState_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let yamlContent = """
        disabled_rules:
          - Force Try
        """
        let configPath = tempDir.appendingPathComponent(".swiftprojectlint.yml")
        try yamlContent.write(to: configPath, atomically: true, encoding: .utf8)

        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = tempDir.path
        viewModel.loadConfigFromProject()

        // Remove Force Try from enabled rules to match the loaded config
        viewModel.enabledRuleNames.remove(.forceTry)
        viewModel.updateDirtyState()
        #expect(viewModel.configIsDirty == false)
    }

    @Test("updateDirtyState is dirty when rules differ from loaded config")
    func updateDirtyStateDirtyDifferentRules() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirtyDiff_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let yamlContent = """
        disabled_rules:
          - Force Try
        """
        let configPath = tempDir.appendingPathComponent(".swiftprojectlint.yml")
        try yamlContent.write(to: configPath, atomically: true, encoding: .utf8)

        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = tempDir.path
        viewModel.loadConfigFromProject()

        // Re-enable Force Try — now differs from loaded config
        viewModel.enabledRuleNames.insert(.forceTry)
        viewModel.updateDirtyState()
        #expect(viewModel.configIsDirty)
    }

    // MARK: - buildConfiguration (tested indirectly via saveConfigToProject)

    @Test("buildConfiguration includes exclusion overrides")
    func buildConfigurationHasExclusions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuildConfig_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = tempDir.path
        viewModel.ruleExclusions = [
            .forceTry: RuleExclusions(excludeTests: true, excludeViews: true)
        ]
        viewModel.saveConfigToProject()

        // Reload and verify the round-trip
        let reloaded = ContentViewModel()
        reloaded.selectedDirectory = tempDir.path
        reloaded.loadConfigFromProject()
        #expect(reloaded.ruleExclusions[.forceTry]?.excludeTests == true)
        #expect(reloaded.ruleExclusions[.forceTry]?.excludeViews == true)
    }

    @Test("buildConfiguration preserves severity overrides from loaded config")
    func buildConfigPreservesSeverity() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SeverityConfig_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let yamlContent = """
        rules:
          Force Try:
            severity: error
            excluded_paths:
              - "Tests/"
        """
        let configPath = tempDir.appendingPathComponent(".swiftprojectlint.yml")
        try yamlContent.write(to: configPath, atomically: true, encoding: .utf8)

        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = tempDir.path
        viewModel.loadConfigFromProject()

        // Save triggers buildConfiguration which should preserve the severity
        viewModel.saveConfigToProject()

        // Reload and verify severity was preserved
        let reloaded = LintConfigurationLoader.load(projectRoot: tempDir.path)
        let forceTryOverride = try #require(reloaded.ruleOverrides[.forceTry])
        #expect(forceTryOverride.severity == .error)
    }

    @Test("updateDirtyState detects changed exclusion paths")
    func updateDirtyStateDetectsChangedExclusions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DirtyExcl_\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let yamlContent = """
        rules:
          Force Try:
            excluded_paths:
              - "Tests/"
        """
        let configPath = tempDir.appendingPathComponent(".swiftprojectlint.yml")
        try yamlContent.write(to: configPath, atomically: true, encoding: .utf8)

        let viewModel = ContentViewModel()
        viewModel.selectedDirectory = tempDir.path
        viewModel.loadConfigFromProject()

        // Change the exclusion — now differs from loaded
        viewModel.ruleExclusions[.forceTry] = RuleExclusions(
            excludeTests: true, excludeViews: true
        )
        viewModel.updateDirtyState()
        #expect(viewModel.configIsDirty)
    }
}

// MARK: - Mock Analyzer

/// A mock `ProjectAnalyzerProtocol` that returns predetermined issues
/// without touching the filesystem or running real analysis.
private struct MockProjectAnalyzer: ProjectAnalyzerProtocol {
    let issues: [LintIssue]

    func analyzeProject(
        at _: String,
        categories _: [PatternCategory]?,
        ruleIdentifiers _: [RuleIdentifier]?,
        detector _: (any SourcePatternDetectorProtocol)?,
        configuration _: LintConfiguration
    ) async -> [LintIssue] {
        await Task.yield()
        return issues
    }
}

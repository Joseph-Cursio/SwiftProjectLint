import Testing
import Foundation
@testable import SwiftProjectLintCore

@Suite
struct LintConfigurationLoaderTests {

    // MARK: - File Loading

    @Test
    func testMissingFileReturnsDefault() {
        let config = LintConfigurationLoader.load(from: "/nonexistent/path.yml")
        #expect(config.disabledRules.isEmpty)
        #expect(config.enabledOnlyRules == nil)
        #expect(config.excludedPaths.isEmpty)
        #expect(config.ruleOverrides.isEmpty)
    }

    @Test
    func testLoadFromProjectRoot() throws {
        let tempDir = NSTemporaryDirectory() + "swiftprojectlint-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let yaml = """
        disabled_rules:
          - "Magic Number"
          - "Print Statement"
        excluded_paths:
          - "Tests/"
        """
        let configPath = (tempDir as NSString).appendingPathComponent(".swiftprojectlint.yml")
        try yaml.write(toFile: configPath, atomically: true, encoding: .utf8)

        let config = LintConfigurationLoader.load(projectRoot: tempDir)
        #expect(config.disabledRules.contains(.magicNumber))
        #expect(config.disabledRules.contains(.printStatement))
        #expect(config.excludedPaths == ["Tests/"])
    }

    // MARK: - YAML Parsing

    @Test
    func testParsesDisabledRules() throws {
        let yaml = """
        disabled_rules:
          - "Force Try"
          - "Force Unwrap"
        """
        let config = loadFromString(yaml)
        #expect(config.disabledRules.contains(.forceTry))
        #expect(config.disabledRules.contains(.forceUnwrap))
    }

    @Test
    func testParsesEnabledOnly() throws {
        let yaml = """
        enabled_only:
          - "Hardcoded Secret"
          - "Unsafe URL"
        """
        let config = loadFromString(yaml)
        #expect(config.enabledOnlyRules?.contains(.hardcodedSecret) == true)
        #expect(config.enabledOnlyRules?.contains(.unsafeURL) == true)
    }

    @Test
    func testDisabledRulesTakePrecedenceOverEnabledOnly() {
        let yaml = """
        disabled_rules:
          - "Magic Number"
        enabled_only:
          - "Force Try"
        """
        let config = loadFromString(yaml)
        // When both specified, disabled_rules takes precedence, enabled_only is ignored
        #expect(config.disabledRules.contains(.magicNumber))
        #expect(config.enabledOnlyRules == nil)
    }

    @Test
    func testParsesRuleOverrides() throws {
        let yaml = """
        rules:
          "Law of Demeter":
            severity: info
            excluded_paths:
              - "Views/"
        """
        let config = loadFromString(yaml)
        let override = try #require(config.ruleOverrides[.lawOfDemeter])
        #expect(override.severity == .info)
        #expect(override.excludedPaths == ["Views/"])
    }

    @Test
    func testIgnoresUnknownRuleNames() {
        let yaml = """
        disabled_rules:
          - "Nonexistent Rule"
          - "Force Try"
        """
        let config = loadFromString(yaml)
        #expect(config.disabledRules.count == 1)
        #expect(config.disabledRules.contains(.forceTry))
    }

    @Test
    func testParsesSeverityValues() throws {
        let yaml = """
        rules:
          "Magic Number":
            severity: error
          "Print Statement":
            severity: warning
          "Date Now":
            severity: info
        """
        let config = loadFromString(yaml)
        #expect(config.ruleOverrides[.magicNumber]?.severity == .error)
        #expect(config.ruleOverrides[.printStatement]?.severity == .warning)
        #expect(config.ruleOverrides[.dateNow]?.severity == .info)
    }

    // MARK: - Helpers

    private func loadFromString(_ yaml: String) -> LintConfiguration {
        let tempFile = NSTemporaryDirectory() + "test-config-\(UUID().uuidString).yml"
        try? yaml.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }
        return LintConfigurationLoader.load(from: tempFile)
    }
}

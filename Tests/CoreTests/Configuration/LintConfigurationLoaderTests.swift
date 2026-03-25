import Testing
import Foundation
@testable import Core

@Suite
struct LintConfigurationLoaderTests {

    // MARK: - File Loading

    // swiftprojectlint:disable Test Missing Require
    @Test
    func testMissingFileReturnsDefault() {
        let config = LintConfigurationLoader.load(from: "/nonexistent/path.yml")
        #expect(config.disabledRules.isEmpty)
        #expect(config.enabledOnlyRules == nil)
        #expect(config.excludedPaths.isEmpty)
        #expect(config.ruleOverrides.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
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

    // swiftprojectlint:disable Test Missing Require
    @Test("invalid YAML (non-dict root) returns default config")
    func testInvalidYAMLReturnsDefault() {
        let yaml = "- just\n- a\n- list"
        let config = loadFromString(yaml)
        #expect(config.disabledRules.isEmpty)
        #expect(config.enabledOnlyRules == nil)
        #expect(config.excludedPaths.isEmpty)
        #expect(config.ruleOverrides.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test("completely invalid YAML returns default config")
    func testMalformedYAMLReturnsDefault() {
        let yaml = "{{{{not yaml at all::::"
        let config = loadFromString(yaml)
        #expect(config.disabledRules.isEmpty)
        #expect(config.enabledOnlyRules == nil)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test("unknown severity string is treated as nil")
    func testUnknownSeverityReturnsNil() {
        let yaml = """
        rules:
          "Magic Number":
            severity: critical
        """
        let config = loadFromString(yaml)
        #expect(config.ruleOverrides[.magicNumber]?.severity == nil)
    }

    @Test("rule override with only excluded_paths and no severity")
    func testRuleOverridePathsOnly() throws {
        let yaml = """
        rules:
          "Print Statement":
            excluded_paths:
              - "Tests/"
              - "Scripts/"
        """
        let config = loadFromString(yaml)
        let override = try #require(config.ruleOverrides[.printStatement])
        #expect(override.severity == nil)
        #expect(override.excludedPaths == ["Tests/", "Scripts/"])
    }

    @Test("enabled_only without disabled_rules is parsed correctly")
    func testEnabledOnlyAlone() throws {
        let yaml = """
        enabled_only:
          - "Force Try"
        """
        let config = loadFromString(yaml)
        let enabledOnly = try #require(config.enabledOnlyRules)
        #expect(enabledOnly.count == 1)
        #expect(enabledOnly.contains(.forceTry))
        #expect(config.disabledRules.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test("empty disabled_rules list parses as empty set")
    func testEmptyDisabledRules() {
        let yaml = """
        disabled_rules: []
        """
        let config = loadFromString(yaml)
        #expect(config.disabledRules.isEmpty)
    }

    // MARK: - Helpers

    private func loadFromString(_ yaml: String) -> LintConfiguration {
        let tempFile = NSTemporaryDirectory() + "test-config-\(UUID().uuidString).yml"
        try? yaml.write(toFile: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }
        return LintConfigurationLoader.load(from: tempFile)
    }
}

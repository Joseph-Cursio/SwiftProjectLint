import Testing
import Foundation
@testable import Core
@testable import SwiftProjectLintRules

@Suite("LintConfigurationWriter")
struct LintConfigurationWriterTests {

    // MARK: - Helpers

    private func writtenContent(_ config: LintConfiguration) throws -> String {
        let tempFile = NSTemporaryDirectory() + "writer-test-\(UUID().uuidString).yml"
        LintConfigurationWriter.write(config, to: tempFile)
        defer { try? FileManager.default.removeItem(atPath: tempFile) }
        return try String(contentsOfFile: tempFile, encoding: .utf8)
    }

    // MARK: - Individual Sections

    @Test("writes disabled_rules section")
    func writesDisabledRules() throws {
        let config = LintConfiguration(
            disabledRules: [.magicNumber, .printStatement]
        )
        let content = try writtenContent(config)
        #expect(content.contains("disabled_rules:"))
        #expect(content.contains("\"Magic Number\""))
        #expect(content.contains("\"Print Statement\""))
    }

    @Test("writes enabled_only section")
    func writesEnabledOnly() throws {
        let config = LintConfiguration(
            enabledOnlyRules: [.forceTry, .forceUnwrap]
        )
        let content = try writtenContent(config)
        #expect(content.contains("enabled_only:"))
        #expect(content.contains("\"Force Try\""))
        #expect(content.contains("\"Force Unwrap\""))
        // Should not contain disabled_rules since none were set
        #expect(content.contains("disabled_rules:") == false)

    }

    @Test("writes excluded_paths section")
    func writesExcludedPaths() throws {
        let config = LintConfiguration(
            excludedPaths: ["Tests/", "Generated/"]
        )
        let content = try writtenContent(config)
        #expect(content.contains("excluded_paths:"))
        #expect(content.contains("\"Tests/\""))
        #expect(content.contains("\"Generated/\""))
    }

    @Test("writes per-rule severity overrides")
    func writesRuleSeverityOverride() throws {
        let config = LintConfiguration(
            ruleOverrides: [
                .magicNumber: .init(severity: .info)
            ]
        )
        let content = try writtenContent(config)
        #expect(content.contains("rules:"))
        #expect(content.contains("\"Magic Number\":"))
        #expect(content.contains("severity: info"))
    }

    @Test("writes per-rule excluded_paths overrides")
    func writesRuleExcludedPathsOverride() throws {
        let config = LintConfiguration(
            ruleOverrides: [
                .printStatement: .init(excludedPaths: ["Tests/", "Scripts/"])
            ]
        )
        let content = try writtenContent(config)
        #expect(content.contains("rules:"))
        #expect(content.contains("\"Print Statement\":"))
        #expect(content.contains("excluded_paths:"))
        #expect(content.contains("\"Tests/\""))
        #expect(content.contains("\"Scripts/\""))
    }

    @Test("writes severity with all three values",
          arguments: [
              (IssueSeverity.error, "error"),
              (IssueSeverity.warning, "warning"),
              (IssueSeverity.info, "info")
          ])
    func writesSeverityValues(severity: IssueSeverity, expected: String) throws {
        let config = LintConfiguration(
            ruleOverrides: [.magicNumber: .init(severity: severity)]
        )
        let content = try writtenContent(config)
        #expect(content.contains("severity: \(expected)"))
    }

    @Test("skips individual rule entry with neither severity nor excluded_paths")
    func skipsEmptyOverride() throws {
        let config = LintConfiguration(
            ruleOverrides: [.magicNumber: .init()]
        )
        let content = try writtenContent(config)
        // The individual rule entry is skipped (no "Magic Number":) even though the rules: header exists
        #expect(content.contains("\"Magic Number\":") == false)

    }

    // MARK: - Combined Config

    @Test("writes combined config with multiple sections")
    func writesCombinedConfig() throws {
        let config = LintConfiguration(
            disabledRules: [.printStatement],
            excludedPaths: ["Generated/"],
            ruleOverrides: [
                .magicNumber: .init(severity: .info, excludedPaths: ["Tests/"])
            ]
        )
        let content = try writtenContent(config)
        #expect(content.contains("disabled_rules:"))
        #expect(content.contains("excluded_paths:"))
        #expect(content.contains("rules:"))
        #expect(content.contains("severity: info"))
    }

    @Test("writes empty config as empty string")
    func writesEmptyConfig() throws {
        let config = LintConfiguration.default
        let content = try writtenContent(config)
        #expect(content.isEmpty)
    }

    // MARK: - Round-trip

    @Test("round-trip: write then load produces equivalent config for disabled_rules")
    func roundTripDisabledRules() throws {
        let original = LintConfiguration(
            disabledRules: [.forceTry, .forceUnwrap, .magicNumber]
        )
        let tempFile = NSTemporaryDirectory() + "roundtrip-\(UUID().uuidString).yml"
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        LintConfigurationWriter.write(original, to: tempFile)
        let loaded = LintConfigurationLoader.load(from: tempFile)

        #expect(loaded.disabledRules == original.disabledRules)
    }

    @Test("round-trip: write then load produces equivalent config for enabled_only")
    func roundTripEnabledOnly() throws {
        let original = LintConfiguration(
            enabledOnlyRules: [.hardcodedSecret, .unsafeURL]
        )
        let tempFile = NSTemporaryDirectory() + "roundtrip-\(UUID().uuidString).yml"
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        LintConfigurationWriter.write(original, to: tempFile)
        let loaded = LintConfigurationLoader.load(from: tempFile)

        #expect(loaded.enabledOnlyRules == original.enabledOnlyRules)
    }

    @Test("round-trip: write then load produces equivalent config for excluded_paths")
    func roundTripExcludedPaths() throws {
        let original = LintConfiguration(
            excludedPaths: ["Tests/", "Generated/", "Vendor/"]
        )
        let tempFile = NSTemporaryDirectory() + "roundtrip-\(UUID().uuidString).yml"
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        LintConfigurationWriter.write(original, to: tempFile)
        let loaded = LintConfigurationLoader.load(from: tempFile)

        #expect(loaded.excludedPaths == original.excludedPaths)
    }

    @Test("round-trip: write then load preserves rule overrides")
    func roundTripRuleOverrides() throws {
        let original = LintConfiguration(
            ruleOverrides: [
                .magicNumber: .init(severity: .info, excludedPaths: ["Tests/"]),
                .printStatement: .init(severity: .error)
            ]
        )
        let tempFile = NSTemporaryDirectory() + "roundtrip-\(UUID().uuidString).yml"
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        LintConfigurationWriter.write(original, to: tempFile)
        let loaded = LintConfigurationLoader.load(from: tempFile)

        #expect(loaded.ruleOverrides[.magicNumber]?.severity == .info)
        #expect(loaded.ruleOverrides[.magicNumber]?.excludedPaths == ["Tests/"])
        #expect(loaded.ruleOverrides[.printStatement]?.severity == .error)
    }

    @Test("round-trip: full config survives write and reload")
    func roundTripFullConfig() throws {
        let original = LintConfiguration(
            disabledRules: [.todoComment, .emptyCatch],
            excludedPaths: ["Vendor/"],
            ruleOverrides: [
                .lawOfDemeter: .init(severity: .warning, excludedPaths: ["Views/"])
            ]
        )
        let tempFile = NSTemporaryDirectory() + "roundtrip-\(UUID().uuidString).yml"
        defer { try? FileManager.default.removeItem(atPath: tempFile) }

        LintConfigurationWriter.write(original, to: tempFile)
        let loaded = LintConfigurationLoader.load(from: tempFile)

        #expect(loaded.disabledRules == original.disabledRules)
        #expect(loaded.excludedPaths == original.excludedPaths)
        #expect(loaded.ruleOverrides[.lawOfDemeter]?.severity == .warning)
        #expect(loaded.ruleOverrides[.lawOfDemeter]?.excludedPaths == ["Views/"])
    }

    @Test("rules are written in sorted order")
    func rulesSortedOrder() throws {
        let config = LintConfiguration(
            disabledRules: [.printStatement, .forceTry, .emptyCatch]
        )
        let content = try writtenContent(config)
        let lines = content.components(separatedBy: "\n")
        let ruleLines = lines.filter { $0.contains("- \"") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // Sorted alphabetically: Catch Without Handling, Force Try, Print Statement
        #expect(ruleLines.count == 3)
        let first = try #require(ruleLines.first)
        #expect(first.contains("Catch Without Handling"))
        let last = try #require(ruleLines.last)
        #expect(last.contains("Print Statement"))
    }
}

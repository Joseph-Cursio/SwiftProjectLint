import Foundation
import SwiftProjectLintConfig
import SwiftProjectLintModels
import Testing

/// What `RuleNameConfigurationAudit` says about a configuration, and that it agrees with what the
/// loader actually does with the same file.
@Suite
struct RuleNameConfigurationAuditTests {

    private func problems(_ yaml: String) -> [RuleNameConfigurationAudit.Problem] {
        RuleNameConfigurationAudit.problems(inYAML: yaml, path: ".swiftprojectlint.yml")
    }

    /// Loads `yaml` through the real loader, so a test can show the audit describes its behaviour.
    private func loaded(_ yaml: String) throws -> LintConfiguration {
        let path = NSTemporaryDirectory() + "rule-name-audit-\(UUID().uuidString).yml"
        try yaml.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        return LintConfigurationLoader.load(from: path)
    }

    // MARK: - Clean

    @Test("a configuration naming only real rules has no problems")
    func cleanConfiguration() {
        let yaml = """
        disabled_rules:
          - "Magic Number"
        rules:
          "Force Unwrap":
            severity: error
        excluded_paths:
          - "Tests/"
        """
        #expect(problems(yaml).isEmpty)
        #expect(problems("").isEmpty)
        #expect(problems("disabled_rules:\n").isEmpty)
    }

    // MARK: - Unknown names

    @Test("an unknown name under each key is reported, with a suggestion when one fits")
    func unknownNamesUnderEveryKey() {
        let yaml = """
        disabled_rules:
          - "magic-number"
        rules:
          "Not A Rule":
            severity: info
        """
        #expect(problems(yaml) == [
            .unknownRule(key: "disabled_rules", name: "magic-number", suggestion: "Magic Number"),
            .unknownRule(key: "rules", name: "Not A Rule", suggestion: nil),
        ])
    }

    @Test("suggestions ignore case, spacing and punctuation, and accept the suppression key")
    func suggestionsMatchLoosely() {
        #expect(RuleNameConfigurationAudit.suggestion(for: "MagicNumber") == "Magic Number")
        #expect(RuleNameConfigurationAudit.suggestion(for: "magic_number") == "Magic Number")
        #expect(RuleNameConfigurationAudit.suggestion(for: RuleIdentifier.forceUnwrap.suppressionKey) == "Force Unwrap")
        #expect(RuleNameConfigurationAudit.suggestion(for: "Definitely Not A Rule") == nil)
        #expect(RuleNameConfigurationAudit.suggestion(for: "  ") == nil)
    }

    // MARK: - enabled_only

    @Test("an enabled_only whose names are all unknown runs nothing, and the loader agrees")
    func enabledOnlyOfUnknownNamesRunsNothing() throws {
        let yaml = "enabled_only:\n  - \"Typo Rule\"\n"
        #expect(problems(yaml) == [
            .unknownRule(key: "enabled_only", name: "Typo Rule", suggestion: nil),
            .enabledOnlyRunsNothing,
        ])
        #expect(try loaded(yaml).enabledOnlyRules == [])
    }

    @Test("an empty enabled_only key runs nothing, and the loader agrees")
    func emptyEnabledOnlyRunsNothing() throws {
        #expect(problems("enabled_only:\n") == [.enabledOnlyRunsNothing])
        #expect(try loaded("enabled_only:\n").enabledOnlyRules == [])
    }

    @Test("one known name among unknown ones keeps enabled_only running")
    func oneKnownNameIsEnough() {
        let yaml = "enabled_only:\n  - \"Typo Rule\"\n  - \"Force Unwrap\"\n"
        #expect(problems(yaml) == [.unknownRule(key: "enabled_only", name: "Typo Rule", suggestion: nil)])
    }

    @Test("enabled_only beside disabled_rules is ignored, and the loader agrees")
    func enabledOnlyIgnoredBesideDisabledRules() throws {
        let yaml = "disabled_rules:\n  - \"Magic Number\"\nenabled_only:\n  - \"Force Unwrap\"\n"
        #expect(problems(yaml) == [.enabledOnlyIgnored])
        #expect(try loaded(yaml).enabledOnlyRules == nil)
    }

    // MARK: - Malformed values and files

    @Test("a rule list written as one string is read as empty, and the loader agrees")
    func scalarRuleListIsNotAList() throws {
        let yaml = "disabled_rules: \"Magic Number\"\n"
        #expect(problems(yaml) == [.notAList(key: "disabled_rules")])
        #expect(try loaded(yaml).disabledRules.isEmpty)

        let scalarEnabled = "enabled_only: \"Force Unwrap\"\n"
        #expect(problems(scalarEnabled) == [.notAList(key: "enabled_only"), .enabledOnlyRunsNothing])
    }

    @Test("a file that is not a YAML mapping is reported")
    func nonMappingFileIsUnreadable() {
        #expect(problems("- just\n- a list\n") == [.unreadable(path: ".swiftprojectlint.yml")])
    }

    @Test("a missing file matters only when the user named it")
    func missingFileOnlyWhenExplicit() {
        let path = "/nonexistent/\(UUID().uuidString).yml"
        #expect(RuleNameConfigurationAudit.problems(atPath: path, explicit: true) == [.fileNotFound(path: path)])
        #expect(RuleNameConfigurationAudit.problems(atPath: path, explicit: false).isEmpty)
    }

    // MARK: - Notice

    @Test("the notice names each problem, and adds the naming hint only for unknown names")
    func noticeWording() {
        let unknown = RuleNameConfigurationAudit.notice(
            for: [.unknownRule(key: "enabled_only", name: "Typo", suggestion: "Force Unwrap"), .enabledOnlyRunsNothing],
            path: "cfg.yml"
        )
        #expect(unknown.contains("cfg.yml has 2 problems that change which rules run."))
        #expect(unknown.contains("enabled_only: 'Typo' is not a rule, so it is ignored. Did you mean 'Force Unwrap'?"))
        #expect(unknown.contains("this run checks nothing"))
        #expect(unknown.contains("Docs/rules/RULES.md"))

        let missing = RuleNameConfigurationAudit.notice(for: [.fileNotFound(path: "x.yml")], path: "x.yml")
        #expect(missing.contains("1 problem that changes which rules run."))
        #expect(missing.contains("Docs/rules/RULES.md") == false)
    }
}

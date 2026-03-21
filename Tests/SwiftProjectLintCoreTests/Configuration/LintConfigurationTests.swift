import Testing
@testable import SwiftProjectLintCore

@Suite
struct LintConfigurationTests {

    // MARK: - resolveRules

    @Test
    func testDefaultConfigReturnsNil() {
        let config = LintConfiguration.default
        let rules = config.resolveRules()
        #expect(rules == nil, "Default config should return nil (no filtering)")
    }

    @Test
    func testDisabledRulesRemovesRules() throws {
        let config = LintConfiguration(
            disabledRules: [.magicNumber, .printStatement]
        )
        let rules = try #require(config.resolveRules())
        #expect(!rules.contains(.magicNumber))
        #expect(!rules.contains(.printStatement))
        #expect(rules.contains(.forceTry))
    }

    @Test
    func testEnabledOnlyRestrictsToSpecificRules() throws {
        let config = LintConfiguration(
            enabledOnlyRules: [.forceTry, .forceUnwrap]
        )
        let rules = try #require(config.resolveRules())
        #expect(rules.contains(.forceTry))
        #expect(rules.contains(.forceUnwrap))
        #expect(!rules.contains(.magicNumber))
    }

    @Test
    func testCLICategoriesFurtherRestrict() throws {
        let config = LintConfiguration(
            disabledRules: [.magicNumber]
        )
        let rules = try #require(
            config.resolveRules(cliCategories: [.codeQuality])
        )
        #expect(!rules.contains(.magicNumber))
        // Rules from other categories should be excluded
        #expect(!rules.contains(.expensiveOperationInViewBody))
        // Code quality rules (minus disabled) should remain
        #expect(rules.contains(.forceTry))
    }

    @Test
    func testCLIRuleIdentifiersOverrideEverything() throws {
        let config = LintConfiguration(
            disabledRules: [.forceTry]
        )
        let rules = try #require(
            config.resolveRules(cliRuleIdentifiers: [.forceTry, .forceUnwrap])
        )
        // CLI ruleIdentifiers take full precedence, ignoring disabled_rules
        #expect(rules.contains(.forceTry))
        #expect(rules.contains(.forceUnwrap))
        #expect(rules.count == 2)
    }

    // MARK: - applyOverrides

    @Test
    func testSeverityOverride() throws {
        let config = LintConfiguration(
            ruleOverrides: [.magicNumber: .init(severity: .info)]
        )
        let issues = [
            LintIssue(
                severity: .warning, message: "Magic number",
                filePath: "Foo.swift", lineNumber: 10,
                suggestion: nil, ruleName: .magicNumber
            )
        ]
        let result = config.applyOverrides(to: issues)
        let issue = try #require(result.first)
        #expect(issue.severity == .info)
    }

    @Test
    func testPerRulePathExclusion() {
        let config = LintConfiguration(
            ruleOverrides: [.printStatement: .init(excludedPaths: ["Tests/"])]
        )
        let issues = [
            LintIssue(
                severity: .info, message: "print()",
                filePath: "Tests/FooTests.swift", lineNumber: 5,
                suggestion: nil, ruleName: .printStatement
            ),
            LintIssue(
                severity: .info, message: "print()",
                filePath: "Sources/Foo.swift", lineNumber: 10,
                suggestion: nil, ruleName: .printStatement
            )
        ]
        let result = config.applyOverrides(to: issues)
        #expect(result.count == 1)
        #expect(result.first?.filePath == "Sources/Foo.swift")
    }

    @Test
    func testNoOverridePassesThrough() {
        let config = LintConfiguration.default
        let issues = [
            LintIssue(
                severity: .warning, message: "test",
                filePath: "Foo.swift", lineNumber: 1,
                suggestion: nil, ruleName: .forceTry
            )
        ]
        let result = config.applyOverrides(to: issues)
        #expect(result.count == 1)
    }
}

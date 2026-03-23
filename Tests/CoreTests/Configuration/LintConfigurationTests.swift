import Testing
import Foundation
@testable import Core

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

    // MARK: - resolveRules edge cases

    @Test("cliCategories alone filters rules (no disabled/enabledOnly)")
    func testCLICategoriesAloneFiltersRules() throws {
        let config = LintConfiguration.default
        let rules = try #require(config.resolveRules(cliCategories: [.security]))
        // Should only contain security rules
        #expect(rules.allSatisfy { $0.category == .security })
        #expect(rules.contains(.hardcodedSecret))
        #expect(rules.contains(.unsafeURL))
        // Non-security rules excluded
        #expect(!rules.contains(.magicNumber))
        #expect(!rules.contains(.forceTry))
    }

    @Test("enabledOnly combined with cliCategories intersects both")
    func testEnabledOnlyWithCLICategories() throws {
        let config = LintConfiguration(
            enabledOnlyRules: [.hardcodedSecret, .forceTry]
        )
        let rules = try #require(config.resolveRules(cliCategories: [.security]))
        // Only rules in both enabledOnly AND the security category
        #expect(rules.contains(.hardcodedSecret))
        #expect(!rules.contains(.forceTry)) // forceTry is codeQuality, not security
    }

    // MARK: - applyOverrides with projectRoot

    @Test("applyOverrides with projectRoot maps basenames to relative paths for glob matching")
    func testApplyOverridesWithProjectRoot() throws {
        // Create a temp project with Swift files
        let tempDir = NSTemporaryDirectory() + "lint-override-test-\(UUID().uuidString)"
        let sourcesDir = tempDir + "/Sources/Views"
        try FileManager.default.createDirectory(atPath: sourcesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        // Create some Swift files
        try "struct HomeView: View {}".write(
            toFile: sourcesDir + "/HomeView.swift", atomically: true, encoding: .utf8
        )
        try "struct Helper {}".write(
            toFile: sourcesDir + "/Helper.swift", atomically: true, encoding: .utf8
        )

        let config = LintConfiguration(
            ruleOverrides: [
                .magicNumber: .init(excludedPaths: ["**/*View.swift"])
            ]
        )

        let issues = [
            LintIssue(
                severity: .warning, message: "Magic number",
                filePath: "HomeView.swift", lineNumber: 1,
                suggestion: nil, ruleName: .magicNumber
            ),
            LintIssue(
                severity: .warning, message: "Magic number",
                filePath: "Helper.swift", lineNumber: 1,
                suggestion: nil, ruleName: .magicNumber
            )
        ]

        let result = config.applyOverrides(to: issues, projectRoot: tempDir)
        // HomeView.swift should be excluded by the **/*View.swift glob
        #expect(result.count == 1)
        #expect(result.first?.filePath == "Helper.swift")
    }

    @Test("applyOverrides glob with plain wildcard matches relative path")
    func testApplyOverridesPlainWildcardGlob() throws {
        let tempDir = NSTemporaryDirectory() + "lint-glob-test-\(UUID().uuidString)"
        let testsDir = tempDir + "/Tests"
        try FileManager.default.createDirectory(atPath: testsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        try "import XCTest".write(
            toFile: testsDir + "/FooTests.swift", atomically: true, encoding: .utf8
        )

        let config = LintConfiguration(
            ruleOverrides: [
                .printStatement: .init(excludedPaths: ["Tests/*.swift"])
            ]
        )

        let issues = [
            LintIssue(
                severity: .info, message: "print()",
                filePath: "FooTests.swift", lineNumber: 1,
                suggestion: nil, ruleName: .printStatement
            )
        ]

        let result = config.applyOverrides(to: issues, projectRoot: tempDir)
        #expect(result.isEmpty, "File in Tests/*.swift should be excluded")
    }

    @Test("applyOverrides substring pattern matches relative path")
    func testApplyOverridesSubstringPattern() throws {
        let tempDir = NSTemporaryDirectory() + "lint-substr-test-\(UUID().uuidString)"
        let vendorDir = tempDir + "/Vendor/Lib"
        try FileManager.default.createDirectory(atPath: vendorDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        try "class Thing {}".write(
            toFile: vendorDir + "/Thing.swift", atomically: true, encoding: .utf8
        )

        let config = LintConfiguration(
            ruleOverrides: [
                .forceTry: .init(excludedPaths: ["Vendor/"])
            ]
        )

        let issues = [
            LintIssue(
                severity: .error, message: "Force try",
                filePath: "Thing.swift", lineNumber: 1,
                suggestion: nil, ruleName: .forceTry
            )
        ]

        let result = config.applyOverrides(to: issues, projectRoot: tempDir)
        #expect(result.isEmpty, "File under Vendor/ should be excluded by substring match")
    }

    @Test("applyOverrides with severity and path exclusion combined")
    func testApplyOverridesSeverityAndPathCombined() throws {
        let tempDir = NSTemporaryDirectory() + "lint-combo-test-\(UUID().uuidString)"
        let srcDir = tempDir + "/Sources"
        try FileManager.default.createDirectory(atPath: srcDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        try "struct App {}".write(
            toFile: srcDir + "/App.swift", atomically: true, encoding: .utf8
        )

        let config = LintConfiguration(
            ruleOverrides: [
                .magicNumber: .init(severity: .info, excludedPaths: ["**/*Test.swift"])
            ]
        )

        let issues = [
            LintIssue(
                severity: .error, message: "Magic number in source",
                filePath: "App.swift", lineNumber: 5,
                suggestion: nil, ruleName: .magicNumber
            )
        ]

        // App.swift doesn't match **/*Test.swift, so it should pass through with severity changed
        let result = config.applyOverrides(to: issues, projectRoot: tempDir)
        let issue = try #require(result.first)
        #expect(issue.severity == .info)
        #expect(issue.message == "Magic number in source")
    }

    @Test("applyOverrides without projectRoot uses filePath as-is for matching")
    func testApplyOverridesWithoutProjectRoot() {
        let config = LintConfiguration(
            ruleOverrides: [
                .printStatement: .init(excludedPaths: ["Tests/"])
            ]
        )
        let issues = [
            LintIssue(
                severity: .info, message: "print()",
                filePath: "Tests/FooTests.swift", lineNumber: 5,
                suggestion: nil, ruleName: .printStatement
            )
        ]
        // Without projectRoot, filePath is used directly — substring "Tests/" matches
        let result = config.applyOverrides(to: issues)
        #expect(result.isEmpty)
    }
}

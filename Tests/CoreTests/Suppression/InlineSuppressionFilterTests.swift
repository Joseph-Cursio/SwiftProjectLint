import Testing
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct InlineSuppressionFilterTests {

    // MARK: - Helpers

    private func issue(rule: RuleIdentifier, line: Int) -> LintIssue {
        LintIssue(
            severity: .warning,
            message: "test",
            filePath: "/test.swift",
            lineNumber: line,
            suggestion: nil,
            ruleName: rule
        )
    }

    // MARK: - disable:this

    @Test func testDisableThisRemovesIssueOnSameLine() {
        let source = """
        // swiftprojectlint:disable:this force-try
        try! riskyCall()
        """
        // Issue is on line 1 (the comment line itself)
        let issues = [issue(rule: .forceTry, line: 1)]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.isEmpty)
    }

    @Test func testDisableThisDoesNotAffectOtherLines() {
        let source = """
        // swiftprojectlint:disable:this force-try
        try! riskyCall()
        """
        let issues = [issue(rule: .forceTry, line: 2)]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.count == 1)
    }

    // MARK: - disable:next

    @Test func testDisableNextRemovesIssueOnFollowingLine() {
        let source = """
        let x = 1
        // swiftprojectlint:disable:next force-try
        try! riskyCall()
        let y = 2
        """
        let issues = [issue(rule: .forceTry, line: 3)]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.isEmpty)
    }

    @Test func testDisableNextDoesNotAffectCommentLine() {
        let source = """
        // swiftprojectlint:disable:next force-try
        try! riskyCall()
        """
        let issues = [issue(rule: .forceTry, line: 1)]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.count == 1)
    }

    @Test func testDisableNextDoesNotAffectTwoLinesDown() {
        let source = """
        // swiftprojectlint:disable:next force-try
        try! ok()
        try! alsoFlagged()
        """
        let issues = [issue(rule: .forceTry, line: 3)]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.count == 1)
    }

    // MARK: - disable / enable region

    @Test func testDisableEnableRegionRemovesIssuesInRange() {
        let source = """
        let a = 1
        // swiftprojectlint:disable force-try
        try! one()
        try! two()
        // swiftprojectlint:enable force-try
        try! three()
        """
        let issues = [
            issue(rule: .forceTry, line: 3),
            issue(rule: .forceTry, line: 4),
            issue(rule: .forceTry, line: 6)
        ]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.count == 1)
        #expect(result[0].lineNumber == 6)
    }

    @Test func testDisableWithoutEnableRemovesRestOfFile() {
        let source = """
        let a = 1
        // swiftprojectlint:disable force-try
        try! one()
        try! two()
        """
        let issues = [
            issue(rule: .forceTry, line: 3),
            issue(rule: .forceTry, line: 4)
        ]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.isEmpty)
    }

    // MARK: - Rule isolation

    @Test func testDifferentRulesAreNotCrossContaminated() {
        let source = "// swiftprojectlint:disable:next force-try"
        let issues = [
            issue(rule: .forceTry, line: 2),
            issue(rule: .forceUnwrap, line: 2)
        ]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.count == 1)
        #expect(result[0].ruleName == .forceUnwrap)
    }

    // MARK: - Disable all rules

    @Test func testDisableAllRulesSuppressesEverything() {
        let source = """
        // swiftprojectlint:disable
        let x = try! foo()
        let y = 42 as! Int
        """
        let issues = [
            issue(rule: .forceTry, line: 2),
            issue(rule: .forceUnwrap, line: 3)
        ]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.isEmpty)
    }

    @Test func testEnableAllRulesAfterDisableAll() {
        let source = """
        // swiftprojectlint:disable
        let x = try! foo()
        // swiftprojectlint:enable
        let y = try! bar()
        """
        let issues = [
            issue(rule: .forceTry, line: 2),
            issue(rule: .forceTry, line: 4)
        ]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.count == 1)
        #expect(result[0].lineNumber == 4)
    }

    // MARK: - No-op cases

    @Test func testEmptyIssuesReturnsEmpty() {
        let source = "// swiftprojectlint:disable force-try"
        let result = InlineSuppressionFilter.filter([], fileContent: source)
        #expect(result.isEmpty)
    }

    @Test func testNoDirectivesReturnsAllIssues() {
        let source = """
        struct Foo {
            let x = try! bar()
        }
        """
        let issues = [issue(rule: .forceTry, line: 2)]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.count == 1)
    }
}

@testable import Core
import Testing

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

    // MARK: - disable:next across an intervening doc comment
    //
    // `disable:next` suppresses exactly `line + 1`, with no notion of what is on
    // that line. When the directive sits above a *documented* declaration, the
    // line it lands on is the doc comment and the declaration is never
    // suppressed.
    //
    // This is not hypothetical and it is not merely inconvenient. SwiftLint's
    // `orphaned_doc_comment` requires the reverse order — a `///` block must be
    // adjacent to its declaration, with no `//` line between — so on any project
    // running both linters the two demands are unsatisfiable, and the "fix" that
    // reorders to satisfy SwiftLint silently disables every `disable:next` in
    // the file. Discovered in SwiftInferProperties, where it disabled 14 of
    // them and the lint run stayed green.

    @Test("disable:next reaches a declaration through its doc comment")
    func testDisableNextSkipsInterveningDocComment() {
        let source = """
        // swiftprojectlint:disable:next force-try
        /// Documented, which is why the directive cannot sit adjacent.
        try! riskyCall()
        """
        // The declaration is on line 3; only line 2 is the doc comment.
        let issues = [issue(rule: .forceTry, line: 3)]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.isEmpty, "the directive must reach past the doc comment")
    }

    @Test("disable:next reaches past a multi-line doc comment and a blank line")
    func testDisableNextSkipsDocCommentBlockAndBlankLine() {
        let source = """
        // swiftprojectlint:disable:next force-try

        /// First line.
        ///
        /// Third line, after an empty doc line.
        // A plain maintainer note, also not code.
        try! riskyCall()
        """
        let issues = [issue(rule: .forceTry, line: 7)]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.isEmpty)
    }

    /// The adjacent case must keep working — this is the shape every existing
    /// use has, and skipping must not shift the target when there is nothing to
    /// skip.
    @Test("disable:next still targets the immediately following line")
    func testDisableNextStillTargetsAdjacentLine() {
        let source = """
        // swiftprojectlint:disable:next force-try
        try! riskyCall()
        try! second()
        """
        let issues = [issue(rule: .forceTry, line: 2), issue(rule: .forceTry, line: 3)]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.map(\.lineNumber) == [3], "only the adjacent line is suppressed")
    }

    /// **The guard against over-skipping.** If the search ran to the next line
    /// bearing an issue rather than the next line bearing *code*, a directive
    /// followed by unrelated code would leap over it and suppress something the
    /// author never pointed at.
    @Test("disable:next does not leap over intervening code")
    func testDisableNextDoesNotSkipCode() {
        let source = """
        // swiftprojectlint:disable:next force-try
        let safe = 1
        try! riskyCall()
        """
        let issues = [issue(rule: .forceTry, line: 3)]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.count == 1, "line 2 is code, so the directive stops there")
    }

    /// A directive as the last line of a file has nothing to point at and must
    /// not crash or wrap around.
    @Test("a trailing disable:next suppresses nothing")
    func testTrailingDisableNextIsInert() {
        let source = """
        try! riskyCall()
        // swiftprojectlint:disable:next force-try
        """
        let issues = [issue(rule: .forceTry, line: 1)]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.count == 1)
    }

    /// **The layout this fix exists to permit**, verbatim from
    /// SwiftInferProperties: the SwiftProjectLint directive on top, then a
    /// maintainer note, then the doc comment sitting directly on its
    /// declaration so SwiftLint's `orphaned_doc_comment` is satisfied too.
    /// Before the fix the directive landed on the note and suppressed nothing.
    @Test("the directive-note-doc-declaration layout suppresses the declaration")
    func testRealWorldDocumentedDeclarationLayout() {
        let source = """
        // swiftprojectlint:disable:next force-try
        // The identically-named type in Tests/Fixtures is sample input this tool
        // parses, not a second production model. Not real duplication.
        /// Confidence in the selected generator. `nil` until selection runs.
        try! riskyCall()
        """
        let issues = [issue(rule: .forceTry, line: 5)]
        let result = InlineSuppressionFilter.filter(issues, fileContent: source)
        #expect(result.isEmpty)
    }
}

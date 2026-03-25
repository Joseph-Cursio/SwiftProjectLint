import Testing
@testable import Core

@Suite
struct InlineSuppressionParserTests {

    // MARK: - disable

    // swiftprojectlint:disable Test Missing Require
    @Test func testDisableSpecificRule() {
        let source = """
        let x = 42 // something
        // swiftprojectlint:disable force-try
        let y = 1
        """
        let directives = InlineSuppressionParser.parse(fileContent: source)
        #expect(directives.count == 1)
        let d = directives[0]
        #expect(d.kind == .disable)
        #expect(d.rules == [.forceTry])
        #expect(d.line == 2)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testDisableAllRules() {
        let source = "// swiftprojectlint:disable"
        let directives = InlineSuppressionParser.parse(fileContent: source)
        #expect(directives.count == 1)
        #expect(directives[0].kind == .disable)
        #expect(directives[0].rules.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testDisableMultipleRulesOnOneLine() {
        let source = "// swiftprojectlint:disable force-try force-unwrap magic-number"
        let directives = InlineSuppressionParser.parse(fileContent: source)
        #expect(directives.count == 1)
        #expect(directives[0].rules == [.forceTry, .forceUnwrap, .magicNumber])
    }

    // MARK: - enable

    // swiftprojectlint:disable Test Missing Require
    @Test func testEnableRule() {
        let source = "// swiftprojectlint:enable force-try"
        let directives = InlineSuppressionParser.parse(fileContent: source)
        #expect(directives.count == 1)
        #expect(directives[0].kind == .enable)
        #expect(directives[0].rules == [.forceTry])
    }

    // MARK: - disable:next

    // swiftprojectlint:disable Test Missing Require
    @Test func testDisableNext() {
        let source = "// swiftprojectlint:disable:next force-try"
        let directives = InlineSuppressionParser.parse(fileContent: source)
        #expect(directives.count == 1)
        #expect(directives[0].kind == .disableNext)
        #expect(directives[0].rules == [.forceTry])
        #expect(directives[0].line == 1)
    }

    // MARK: - disable:this

    // swiftprojectlint:disable Test Missing Require
    @Test func testDisableThis() {
        let source = "// swiftprojectlint:disable:this force-try"
        let directives = InlineSuppressionParser.parse(fileContent: source)
        #expect(directives.count == 1)
        #expect(directives[0].kind == .disableThis)
        #expect(directives[0].rules == [.forceTry])
    }

    // MARK: - Edge cases

    // swiftprojectlint:disable Test Missing Require
    @Test func testCaseInsensitiveRuleName() {
        let source = "// swiftprojectlint:disable Force-Try"
        let directives = InlineSuppressionParser.parse(fileContent: source)
        #expect(directives.count == 1)
        #expect(directives[0].rules == [.forceTry])
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testUnknownRuleNameIsIgnored() {
        let source = "// swiftprojectlint:disable not-a-real-rule"
        let directives = InlineSuppressionParser.parse(fileContent: source)
        // Directive is still parsed, but its rules set is empty (unknown token dropped)
        #expect(directives.count == 1)
        #expect(directives[0].rules.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testMalformedKeywordIsIgnored() {
        let source = "// swiftprojectlint:bogus force-try"
        let directives = InlineSuppressionParser.parse(fileContent: source)
        #expect(directives.isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testNoDirectivesReturnsEmpty() {
        let source = """
        struct Foo {
            let x = 42
        }
        """
        #expect(InlineSuppressionParser.parse(fileContent: source).isEmpty)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testIndentedCommentIsParsed() {
        let source = "    // swiftprojectlint:disable force-try"
        let directives = InlineSuppressionParser.parse(fileContent: source)
        #expect(directives.count == 1)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func testLineNumberIsCorrect() {
        let source = """
        line one
        line two
        // swiftprojectlint:disable force-try
        line four
        """
        let directives = InlineSuppressionParser.parse(fileContent: source)
        #expect(directives[0].line == 3)
    }
}

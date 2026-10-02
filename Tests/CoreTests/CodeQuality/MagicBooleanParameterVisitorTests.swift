@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct MagicBooleanParameterVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = MagicBooleanParameterVisitor(patternCategory: .codeQuality)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .magicBooleanParameter }
    }

    // MARK: - Positive: flags magic boolean parameters

    @Test func testFlagsMultipleUnlabeledBooleans() throws {
        let source = """
        configureView(true, false, true)
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("3"))
        #expect(issue.message.contains("unlabeled"))
    }

    @Test func testFlagsMixedArgsWithUnlabeledBool() {
        let source = """
        process(data, true)
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsTwoUnlabeledBooleans() {
        let source = """
        configure(true, false)
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsMemberFunctionCall() {
        let source = """
        view.setup(data, false, true)
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForLabeledBooleans() {
        let source = """
        configureView(animated: true, recursive: false, verbose: true)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForSingleBooleanArg() {
        let source = """
        setEnabled(false)
        toggle(true)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForPrint() {
        let source = """
        print(value, true)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForXCTAssert() {
        let source = """
        XCTAssertEqual(result, true)
        XCTAssertTrue(flag)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNoBooleansAtAll() {
        let source = """
        process(data, count, name)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForLabeledBoolWithOtherArgs() {
        let source = """
        render(view, animated: false)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    // MARK: - Message wording

    // The count and the noun must agree. Mutation testing changed the plural's condition and
    // swapped its branches, and no test noticed: none read the noun.
    @Test func testOneUnlabeledBoolIsSingular() throws {
        let issue = try #require(filteredIssues("setFlag(item, true)").first)
        #expect(issue.message.contains("1 unlabeled boolean parameter —"))
    }

    @Test func testSeveralUnlabeledBoolsArePlural() throws {
        let issue = try #require(filteredIssues("configure(true, false)").first)
        #expect(issue.message.contains("2 unlabeled boolean parameters —"))
    }
}

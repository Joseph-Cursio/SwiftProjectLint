import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

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

    @Test func testFlagsMixedArgsWithUnlabeledBool() throws {
        let source = """
        process(data, true)
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsTwoUnlabeledBooleans() throws {
        let source = """
        configure(true, false)
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    @Test func testFlagsMemberFunctionCall() throws {
        let source = """
        view.setup(data, false, true)
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForLabeledBooleans() throws {
        let source = """
        configureView(animated: true, recursive: false, verbose: true)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForSingleBooleanArg() throws {
        let source = """
        setEnabled(false)
        toggle(true)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForPrint() throws {
        let source = """
        print(value, true)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForXCTAssert() throws {
        let source = """
        XCTAssertEqual(result, true)
        XCTAssertTrue(flag)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNoBooleansAtAll() throws {
        let source = """
        process(data, count, name)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForLabeledBoolWithOtherArgs() throws {
        let source = """
        render(view, animated: false)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

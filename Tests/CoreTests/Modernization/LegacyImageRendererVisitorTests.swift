import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct LegacyImageRendererVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = LegacyImageRendererVisitor(patternCategory: .modernization)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .legacyImageRenderer }
    }

    // MARK: - Positive: flags UIGraphicsImageRenderer

    @Test func testFlagsInstantiation() throws {
        let source = """
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("UIGraphicsImageRenderer"))
    }

    @Test func testFlagsTypeAnnotation() throws {
        let source = """
        let renderer: UIGraphicsImageRenderer = makeRenderer()
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForImageRenderer() throws {
        let source = """
        let renderer = ImageRenderer(content: myView)
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForUnrelatedTypes() throws {
        let source = """
        let view = UIView()
        let image = UIImage(named: "test")
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

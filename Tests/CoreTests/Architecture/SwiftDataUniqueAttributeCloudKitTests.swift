import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct SwiftDataUniqueAttributeCloudKitTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = SwiftDataUniqueAttributeCloudKitVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .swiftDataUniqueAttributeCloudKit }
    }

    // MARK: - Positive: flags @Attribute(.unique) in @Model

    @Test func testFlagsUniqueAttributeInModel() throws {
        let source = """
        @Model
        class User {
            @Attribute(.unique) var email: String
            var name: String
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("email"))
        #expect(issue.message.contains("CloudKit"))
    }

    @Test func testFlagsMultipleUniqueAttributes() throws {
        let source = """
        @Model
        class Product {
            @Attribute(.unique) var sku: String
            @Attribute(.unique) var barcode: String
            var name: String
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueWithoutUniqueAttribute() throws {
        let source = """
        @Model
        class User {
            var email: String
            var name: String
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForOtherAttributes() throws {
        let source = """
        @Model
        class Item {
            @Attribute(.spotlight) var title: String
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNonModelClass() throws {
        let source = """
        class RegularClass {
            @Attribute(.unique) var identifier: String
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForStruct() throws {
        let source = """
        struct DataModel {
            @Attribute(.unique) var identifier: String
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

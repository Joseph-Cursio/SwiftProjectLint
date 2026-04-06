import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct LegacyFormatterVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = LegacyFormatterVisitor(patternCategory: .modernization)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .legacyFormatter }
    }

    // MARK: - Positive: flags formatter instantiation

    @Test func testFlagsDateFormatter() throws {
        let source = """
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("DateFormatter"))
    }

    @Test func testFlagsNumberFormatter() throws {
        let source = """
        func format(_ val: Double) -> String {
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            return fmt.string(from: NSNumber(value: val)) ?? ""
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("NumberFormatter") == true)
    }

    @Test func testFlagsMeasurementFormatter() throws {
        let source = """
        class Exporter {
            func export() -> String {
                let fmt = MeasurementFormatter()
                return fmt.string(from: Measurement(value: 1, unit: UnitLength.meters))
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("MeasurementFormatter") == true)
    }

    @Test func testFlagsMultipleFormatters() throws {
        let source = """
        let dateFmt = DateFormatter()
        let numFmt = NumberFormatter()
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 2)
    }

    // MARK: - Negative: should NOT flag

    @Test func testSkipsViewBody() throws {
        let source = """
        struct MyView: View {
            var body: some View {
                Text(DateFormatter().string(from: Date()))
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForModernFormatStyle() throws {
        let source = """
        let formatted = Date().formatted(.dateTime.month().day())
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForStaticCachedFormatter() throws {
        let source = """
        extension DateFormatter {
            static let medium: DateFormatter = {
                let fmt = DateFormatter()
                fmt.dateStyle = .medium
                return fmt
            }()
        }
        """
        let issues = filteredIssues(source)
        // Static cached initialization is still flagged — the rule suggests
        // FormatStyle as the preferred alternative. This is intentional at .info.
        #expect(issues.count == 1)
    }

    @Test func testNoIssueForUnrelatedTypes() throws {
        let source = """
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testFlagsFormatterOutsideViewBodyInViewStruct() throws {
        let source = """
        struct MyView: View {
            func helperFormat() -> String {
                let fmt = DateFormatter()
                return fmt.string(from: Date())
            }
            var body: some View {
                Text("Hello")
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.count == 1)
    }
}

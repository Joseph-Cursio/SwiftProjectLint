import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct IOS17ObservationMigrationVisitorTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = IOS17ObservationMigrationVisitor(patternCategory: .modernization)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    private func filteredIssues(_ source: String) -> [LintIssue] {
        analyzeSource(source).filter { $0.ruleName == .ios17ObservationMigration }
    }

    // MARK: - Positive: flags migration candidates

    @Test func testHighReadinessSimplePublished() throws {
        let source = """
        class ProfileViewModel: ObservableObject {
            @Published var name: String = ""
            @Published var avatar: String?
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issues.count == 1)
        #expect(issue.message.contains("high"))
        #expect(issue.message.contains("ProfileViewModel"))
    }

    @Test func testMediumReadinessManualObjectWillChange() throws {
        let source = """
        class CounterViewModel: ObservableObject {
            @Published var count: Int = 0
            func increment() {
                objectWillChange.send()
                count += 1
            }
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("medium"))
    }

    @Test func testLowReadinessNoPublished() throws {
        let source = """
        class EmptyViewModel: ObservableObject {
            var name: String = ""
        }
        """
        let issues = filteredIssues(source)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("low"))
    }

    // MARK: - Negative: should NOT flag

    @Test func testNoIssueForObservableClass() throws {
        let source = """
        @Observable
        class ProfileViewModel {
            var name: String = ""
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForNonObservableObject() throws {
        let source = """
        class PlainClass {
            @Published var name: String = ""
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesCombinePublisherUsage() throws {
        let source = """
        class StreamViewModel: ObservableObject {
            @Published var items: [String] = []
            func setup() {
                let sub = $items.sink { _ in }
            }
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testSuppressesNSObjectSubclass() throws {
        let source = """
        class LegacyModel: NSObject, ObservableObject {
            @Published var value: Int = 0
        }
        """
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }

    @Test func testNoIssueForStruct() throws {
        let source = """
        struct DataModel: ObservableObject {
            @Published var value: Int = 0
        }
        """
        // Struct can't actually conform to ObservableObject but visitor only checks ClassDeclSyntax
        let issues = filteredIssues(source)
        #expect(issues.isEmpty)
    }
}

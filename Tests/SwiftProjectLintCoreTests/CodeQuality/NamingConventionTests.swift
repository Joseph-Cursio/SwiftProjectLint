import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import SwiftProjectLintCore

struct NamingConventionTests {

    // MARK: - Test Helpers

    private func createVisitor() -> NamingConventionVisitor {
        let pattern = SyntaxPattern(
            name: .protocolNamingSuffix,
            visitor: NamingConventionVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "",
            suggestion: "",
            description: ""
        )
        let visitor = NamingConventionVisitor(pattern: pattern)
        visitor.setFilePath("TestFile.swift")
        return visitor
    }

    private func detectIssues(in sourceCode: String) -> [LintIssue] {
        let visitor = createVisitor()
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        return visitor.detectedIssues
    }

    // MARK: - Test Case Types

    struct DetectionCase: CustomTestStringConvertible, Sendable {
        let label: String
        let sourceCode: String
        let expectedCount: Int

        var testDescription: String { label }
    }

    struct SuggestionCase: CustomTestStringConvertible, Sendable {
        let label: String
        let sourceCode: String
        let expectedSuggestion: String

        var testDescription: String { label }
    }

    // MARK: - Parameterized Detection Tests

    static let detectionCases: [DetectionCase] = [
        DetectionCase(
            label: "protocol without suffix",
            sourceCode: "protocol Requestable { func perform() async throws }",
            expectedCount: 1
        ),
        DetectionCase(
            label: "protocol with suffix",
            sourceCode: "protocol RequestableProtocol { func perform() async throws }",
            expectedCount: 0
        ),
        DetectionCase(
            label: "actor without suffix",
            sourceCode: "actor ImageDownloader { func download() async {} }",
            expectedCount: 1
        ),
        DetectionCase(
            label: "actor with suffix",
            sourceCode: "actor ImageDownloaderActor { func download() async {} }",
            expectedCount: 0
        ),
        DetectionCase(
            label: "property wrapper struct without suffix",
            sourceCode: "@propertyWrapper struct Clamped<Value: Comparable> { var wrappedValue: Value }",
            expectedCount: 1
        ),
        DetectionCase(
            label: "property wrapper struct with suffix",
            sourceCode: "@propertyWrapper struct ClampedWrapper<Value: Comparable> { var wrappedValue: Value }",
            expectedCount: 0
        ),
        DetectionCase(
            label: "property wrapper class without suffix",
            sourceCode: """
            @propertyWrapper class Observable<Value> {
                var wrappedValue: Value
                init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
            }
            """,
            expectedCount: 1
        ),
        DetectionCase(
            label: "regular struct not flagged",
            sourceCode: "struct UserSettings { var name: String }",
            expectedCount: 0
        ),
        DetectionCase(
            label: "regular class not flagged",
            sourceCode: "class Manager { var name: String = \"\" }",
            expectedCount: 0
        )
    ]

    @Test("Detects or skips based on naming suffix", arguments: detectionCases)
    func detectsNamingIssues(_ testCase: DetectionCase) {
        let issues = detectIssues(in: testCase.sourceCode)
        #expect(issues.count == testCase.expectedCount)

        for issue in issues {
            #expect(issue.severity == .info)
        }
    }

    // MARK: - Parameterized Suggestion Tests

    static let suggestionCases: [SuggestionCase] = [
        SuggestionCase(
            label: "protocol suggests Protocol suffix",
            sourceCode: "protocol Fetchable { func fetch() }",
            expectedSuggestion: "FetchableProtocol"
        ),
        SuggestionCase(
            label: "actor suggests Actor suffix",
            sourceCode: "actor CacheService { func clear() async {} }",
            expectedSuggestion: "CacheServiceActor"
        ),
        SuggestionCase(
            label: "property wrapper suggests Wrapper suffix",
            sourceCode: "@propertyWrapper struct UserDefault<Value> { var wrappedValue: Value }",
            expectedSuggestion: "UserDefaultWrapper"
        )
    ]

    @Test("Suggestion contains corrected name", arguments: suggestionCases)
    func suggestionContainsCorrectedName(_ testCase: SuggestionCase) throws {
        let issues = detectIssues(in: testCase.sourceCode)
        let issue = try #require(issues.first)
        let suggestion = try #require(issue.suggestion)
        #expect(suggestion.contains(testCase.expectedSuggestion))
    }

    // MARK: - Multi-Declaration Tests

    @Test("Multiple protocols with mixed naming")
    func multipleProtocolsMixedNaming() {
        let sourceCode = """
        protocol NetworkServiceProtocol { func fetch() async throws }
        protocol DataStore { func save() }
        protocol CacheManagerProtocol { func clear() }
        protocol Logging { func log(_ message: String) }
        """

        let issues = detectIssues(in: sourceCode)
        #expect(issues.count == 2)

        let issueMessages = issues.map(\.message)
        #expect(issueMessages.contains { $0.contains("DataStore") })
        #expect(issueMessages.contains { $0.contains("Logging") })
    }

    @Test("All three rules fire in same file")
    func allThreeRulesFireInSameFile() {
        let sourceCode = """
        protocol Fetchable { func fetch() }
        actor DataService { func process() async {} }
        @propertyWrapper struct Validated<Value> { var wrappedValue: Value }
        """

        let issues = detectIssues(in: sourceCode)
        #expect(issues.count == 3)

        let messages = issues.map(\.message)
        #expect(messages.contains { $0.contains("Protocol") })
        #expect(messages.contains { $0.contains("Actor") })
        #expect(messages.contains { $0.contains("wrapper") })
    }
}

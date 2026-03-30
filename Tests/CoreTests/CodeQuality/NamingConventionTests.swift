import Testing
import Foundation
import SwiftParser
import SwiftSyntax
@testable import Core
@testable import SwiftProjectLintRules

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
            label: "actor without suffix (agent name) — only actorNamingSuffix fires",
            sourceCode: "actor ImageDownloader { func download() async {} }",
            expectedCount: 1
        ),
        DetectionCase(
            label: "actor without suffix (passive name) — both actorNamingSuffix and actorAgentName fire",
            sourceCode: "actor VectorStore { func search() async -> [Float] { [] } }",
            expectedCount: 2
        ),
        DetectionCase(
            label: "actor with Actor suffix — no issues",
            sourceCode: "actor ImageDownloaderActor { func download() async {} }",
            expectedCount: 0
        ),
        DetectionCase(
            label: "actor with agent-noun name and Actor suffix — no issues",
            sourceCode: "actor VectorStoreActor { func search() async -> [Float] { [] } }",
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
            label: "regular class with agent-noun name fires nonActorAgentSuffix",
            sourceCode: "class Manager { var name: String = \"\" }",
            expectedCount: 1
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

    @Test("All naming rules fire in same file")
    func allNamingRulesFireInSameFile() {
        // DataService: no agent suffix, no Actor suffix → actorNamingSuffix + actorAgentName (2 issues)
        // Fetchable: no Protocol suffix → protocolNamingSuffix (1 issue)
        // Validated: no Wrapper suffix → propertyWrapperNamingSuffix (1 issue)
        let sourceCode = """
        protocol Fetchable { func fetch() }
        actor DataService { func process() async {} }
        @propertyWrapper struct Validated<Value> { var wrappedValue: Value }
        """

        let issues = detectIssues(in: sourceCode)
        #expect(issues.count == 4)

        let ruleNames = Set(issues.compactMap(\.ruleName))
        #expect(ruleNames.contains(.protocolNamingSuffix))
        #expect(ruleNames.contains(.actorNamingSuffix))
        #expect(ruleNames.contains(.actorAgentName))
        #expect(ruleNames.contains(.propertyWrapperNamingSuffix))
    }

    @Test("actorAgentName does not fire for agent-noun actor names")
    func actorAgentNameSuppressedForAgentNouns() {
        let sourceCode = """
        actor WorkspaceIndexer { func index() async {} }
        actor ModelRouter { func route() async -> String { "" } }
        actor SkillMigrator { func migrate() async {} }
        """
        let issues = detectIssues(in: sourceCode)
        // Each fires only actorNamingSuffix, not actorAgentName
        #expect(issues.allSatisfy { $0.ruleName == .actorNamingSuffix })
        #expect(issues.count == 3)
    }

    @Test("actorAgentName fires for passive-sounding actor names")
    func actorAgentNameFiresForPassiveNames() {
        let sourceCode = """
        actor VectorStore { }
        actor KnowledgeGraph { }
        actor BeadStore { }
        """
        let issues = detectIssues(in: sourceCode)
        let agentNameIssues = issues.filter { $0.ruleName == .actorAgentName }
        #expect(agentNameIssues.count == 3)
        #expect(agentNameIssues.allSatisfy { $0.message.contains("passive") })
    }

    // MARK: - Non-Actor Agent Suffix Tests (Rule 3, opt-in)

    @Test("nonActorAgentSuffix fires for class/struct with agent-noun name")
    func nonActorAgentSuffixFiresForAgentNounClass() {
        let sourceCode = """
        class DataManager { var items: [String] = [] }
        struct FileProcessor { var path: String = "" }
        class NetworkRouter { }
        """
        let issues = detectIssues(in: sourceCode)
        let rule3Issues = issues.filter { $0.ruleName == .nonActorAgentSuffix }
        #expect(rule3Issues.count == 3)
        #expect(rule3Issues.allSatisfy { $0.message.contains("agent-noun") })
    }

    @Test("nonActorAgentSuffix does not fire when name ends with Agent")
    func nonActorAgentSuffixSuppressedForAgentSuffix() {
        let sourceCode = """
        class DataManagerAgent { var items: [String] = [] }
        struct FileProcessorAgent { var path: String = "" }
        """
        let issues = detectIssues(in: sourceCode)
        let rule3Issues = issues.filter { $0.ruleName == .nonActorAgentSuffix }
        #expect(rule3Issues.isEmpty)
    }

    @Test("nonActorAgentSuffix does not fire for property wrappers ending in -er")
    func nonActorAgentSuffixSkipsPropertyWrappers() {
        let sourceCode = """
        @propertyWrapper struct ClampedWrapper<Value: Comparable> { var wrappedValue: Value }
        @propertyWrapper class UserDefaultWrapper<Value> {
            var wrappedValue: Value
            init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
        }
        """
        let issues = detectIssues(in: sourceCode)
        let rule3Issues = issues.filter { $0.ruleName == .nonActorAgentSuffix }
        #expect(rule3Issues.isEmpty)
    }

    @Test("nonActorAgentSuffix does not fire for non-agent-noun names")
    func nonActorAgentSuffixSkipsNonAgentNames() {
        let sourceCode = """
        class VectorStore { }
        struct KnowledgeGraph { }
        class UserSettings { }
        """
        let issues = detectIssues(in: sourceCode)
        let rule3Issues = issues.filter { $0.ruleName == .nonActorAgentSuffix }
        #expect(rule3Issues.isEmpty)
    }

    @Test("nonActorAgentSuffix suggestion mentions both actor and Agent options")
    func nonActorAgentSuffixSuggestionMentionsBothOptions() throws {
        let sourceCode = "class DataProcessor { }"
        let issues = detectIssues(in: sourceCode)
        let rule3Issue = try #require(issues.first { $0.ruleName == .nonActorAgentSuffix })
        let suggestion = try #require(rule3Issue.suggestion)
        #expect(suggestion.contains("actor"))
        #expect(suggestion.contains("Agent"))
    }
}

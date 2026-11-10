@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

extension NamingConventionTests {
    // MARK: - Test-File Exemption (slice B)

    /// Helper: parse + walk source against a specific `filePath`, so the
    /// `BasePatternVisitor.isTestOrFixtureFile()` heuristic can exercise
    /// path-based exemptions. The base `detectIssues(in:)` helper sets
    /// `"TestFile.swift"` (no `s`), which deliberately doesn't match the
    /// `Tests` substring check — so these tests are isolated.
    func detectIssues(in sourceCode: String, filePath: String) -> [LintIssue] {
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
        visitor.setFilePath(filePath)
        let sourceFile = Parser.parse(source: sourceCode)
        visitor.walk(sourceFile)
        return visitor.detectedIssues
    }

    @Test("actorNamingSuffix and actorAgentName silenced under Tests/ path")
    func actorRulesSilencedInTestFile() {
        // Both rules would normally fire on these names — passive Counter
        // (no Actor suffix, no agent-noun suffix) trips both rules in
        // production code. In a test file, fixture actors are scoped and
        // verbose suffixes don't pay off. Cross-adopter evidence:
        // SwiftIdempotency package scan (2026-04-26) showed 13 fires of
        // these two rules across test fixtures alone.
        let sourceCode = """
        actor Counter { }
        actor Gate { }
        actor VectorStore { }
        """
        let issues = detectIssues(
            in: sourceCode,
            filePath: "/path/to/Tests/MyPackageTests/MyTests.swift"
        )
        let actorIssues = issues.filter {
            $0.ruleName == .actorNamingSuffix || $0.ruleName == .actorAgentName
        }
        #expect(actorIssues.isEmpty)
    }

    @Test("actorNamingSuffix and actorAgentName still fire under Sources/ path")
    func actorRulesFireInProductionFile() {
        // Regression check — the test-file exemption must not leak into
        // production paths. Same source as the test-file case above
        // should still fire both rules.
        let sourceCode = """
        actor Counter { }
        actor VectorStore { }
        """
        let issues = detectIssues(
            in: sourceCode,
            filePath: "/path/to/Sources/MyPackage/MyType.swift"
        )
        let suffixIssues = issues.filter { $0.ruleName == .actorNamingSuffix }
        let agentIssues = issues.filter { $0.ruleName == .actorAgentName }
        #expect(suffixIssues.count == 2)  // Both lack Actor suffix
        #expect(agentIssues.count == 1)   // Counter has -er; only VectorStore is passive
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

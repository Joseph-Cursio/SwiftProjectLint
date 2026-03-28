import Testing
import SwiftSyntax
import SwiftParser
@testable import Core

/// Coverage tests for uncovered paths in PublicInAppTargetVisitor.swift:
/// - ActorDeclSyntax visit (lines 33-36)
/// - TypeAliasDeclSyntax visit (lines 63-66)
@Suite("PublicInAppTarget Coverage Tests")
struct PublicInAppTargetCoverageTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let pattern = PublicInAppTarget().pattern
        let visitor = PublicInAppTargetVisitor(pattern: pattern)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "Test.swift", tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath("Test.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .publicInAppTarget }
    }

    // MARK: - Actor declaration (lines 33-36)

    @Test("flags public actor declaration")
    func flagsPublicActor() throws {
        let issues = analyze("public actor DataManager { }")
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("public actor DataManager"))
    }

    @Test("does not flag internal actor declaration")
    func doesNotFlagInternalActor() {
        let issues = analyze("actor DataManager { }")
        #expect(issues.isEmpty)
    }

    @Test("flags open actor-like class but not actors with open")
    func flagsOpenOnClass() throws {
        // Actors can't be "open" in Swift, but open classes can
        let issues = analyze("open class DataController { }")
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("open class DataController"))
    }

    // MARK: - TypeAlias declaration (lines 63-66)

    @Test("flags public typealias declaration")
    func flagsPublicTypealias() throws {
        let issues = analyze("public typealias UserID = String")
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("public typealias UserID"))
    }

    @Test("does not flag internal typealias declaration")
    func doesNotFlagInternalTypealias() {
        let issues = analyze("typealias UserID = String")
        #expect(issues.isEmpty)
    }

    @Test("flags multiple public typealiases")
    func flagsMultiplePublicTypealiases() {
        let issues = analyze("""
        public typealias Identifier = UUID
        public typealias Callback = () -> Void
        typealias InternalAlias = Int
        """)
        #expect(issues.count == 2)
    }

    // MARK: - Combined actor and typealias

    @Test("flags both public actor and public typealias in same file")
    func flagsBothActorAndTypealias() {
        let issues = analyze("""
        public actor NetworkManager {
            func fetch() { }
        }
        public typealias Response = Data
        """)
        #expect(issues.count == 2)
    }
}

@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ArchitectureSingletonUsageTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = SingletonUsageVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    // MARK: - Detects singleton on service-like types

    @Test func testDetectsSingletonOnServiceType() throws {
        let source = """
        class Coordinator {
            func run() { DataManager.shared.fetch() }
        }
        """
        let issues = analyzeSource(source)
        let singletonIssues = issues.filter { $0.ruleName == .singletonUsage }
        let issue = try #require(singletonIssues.first)
        #expect(issue.message.contains("DataManager"))
    }

    @Test func testDetectsSingletonOnRepositoryType() throws {
        let source = """
        class Presenter {
            func load() { UserRepository.shared.getAll() }
        }
        """
        let issues = analyzeSource(source)
        let singletonIssues = issues.filter { $0.ruleName == .singletonUsage }
        let issue = try #require(singletonIssues.first)
        #expect(issue.message.contains("UserRepository"))
    }

    @Test func testDetectsMultipleSingletons() {
        let source = """
        class Setup {
            func configure() {
                DataManager.shared.setup()
                AnalyticsService.shared.initialize()
            }
        }
        """
        let issues = analyzeSource(source)
        let singletonIssues = issues.filter { $0.ruleName == .singletonUsage }
        #expect(singletonIssues.count == 2)
    }

    // MARK: - No issue for non-service singletons

    @Test func testNoIssueForNonServiceSingleton() {
        let source = """
        class Connector {
            func send() { URLSession.shared.dataTask(with: URL(string: "")!) }
        }
        """
        let issues = analyzeSource(source)
        let singletonIssues = issues.filter { $0.ruleName == .singletonUsage }
        #expect(singletonIssues.isEmpty)
    }

    @Test func testNoIssueForNonSharedMember() {
        let source = """
        class Owner {
            func build() { DataManager.default }
        }
        """
        let issues = analyzeSource(source)
        let singletonIssues = issues.filter { $0.ruleName == .singletonUsage }
        #expect(singletonIssues.isEmpty)
    }

    // MARK: - Test-file exemption

    @Test func testNoIssueInTestFile() {
        // A unit test calling the real `.shared` singleton is the test using
        // production code, not a coupling smell — exempt test files.
        let source = """
        final class ProjectParserTests {
            func testParse() { _ = ProjectParser.shared.parse() }
        }
        """
        let issues = analyzeSource(source, filePath: "MyAppTests/ProjectParserTests.swift")
        let singletonIssues = issues.filter { $0.ruleName == .singletonUsage }
        #expect(singletonIssues.isEmpty)
    }

    @Test func testStillFlagsInProductionFile() throws {
        // The same access in a production file must still be flagged — the
        // exemption is scoped to test/fixture files only.
        let source = """
        final class ProjectParserTests {
            func testParse() { _ = ProjectParser.shared.parse() }
        }
        """
        let issues = analyzeSource(source, filePath: "Sources/App/AppState.swift")
        let singletonIssues = issues.filter { $0.ruleName == .singletonUsage }
        let issue = try #require(singletonIssues.first)
        #expect(issue.message.contains("ProjectParser"))
    }

    @Test func testNoIssueForInstanceSharedProperty() {
        // base is not a DeclReferenceExprSyntax with a service-like name
        let source = """
        class Owner {
            let dm = DataManager()
            func run() { dm.shared }
        }
        """
        let issues = analyzeSource(source)
        let singletonIssues = issues.filter { $0.ruleName == .singletonUsage }
        // dm is not a service-like type name (lowercase), so no issue
        #expect(singletonIssues.isEmpty)
    }
}

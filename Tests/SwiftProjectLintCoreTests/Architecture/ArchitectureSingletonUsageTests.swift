import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

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
        #expect(singletonIssues.count == 1)
        #expect(singletonIssues[0].message.contains("DataManager"))
    }

    @Test func testDetectsSingletonOnRepositoryType() throws {
        let source = """
        class Presenter {
            func load() { UserRepository.shared.getAll() }
        }
        """
        let issues = analyzeSource(source)
        let singletonIssues = issues.filter { $0.ruleName == .singletonUsage }
        #expect(singletonIssues.count == 1)
        #expect(singletonIssues[0].message.contains("UserRepository"))
    }

    @Test func testDetectsMultipleSingletons() throws {
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

    @Test func testNoIssueForNonServiceSingleton() throws {
        let source = """
        class Connector {
            func send() { URLSession.shared.dataTask(with: URL(string: "")!) }
        }
        """
        let issues = analyzeSource(source)
        let singletonIssues = issues.filter { $0.ruleName == .singletonUsage }
        #expect(singletonIssues.isEmpty)
    }

    @Test func testNoIssueForNonSharedMember() throws {
        let source = """
        class Owner {
            func build() { DataManager.default }
        }
        """
        let issues = analyzeSource(source)
        let singletonIssues = issues.filter { $0.ruleName == .singletonUsage }
        #expect(singletonIssues.isEmpty)
    }

    @Test func testNoIssueForInstanceSharedProperty() throws {
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

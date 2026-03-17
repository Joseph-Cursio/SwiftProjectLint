import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

@Suite
@MainActor
struct ArchitectureConcreteTypeUsageTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = ConcreteTypeUsageVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    // MARK: - Function parameter

    @Test func testDetectsConcreteTypeInFunctionParameter() throws {
        let source = """
        class Setup {
            func configure(service: APIService) { }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.count == 1)
        #expect(concreteIssues[0].message.contains("APIService"))
        #expect(concreteIssues[0].message.contains("service"))
    }

    // MARK: - Initializer parameter

    @Test func testDetectsConcreteTypeInInitializerParameter() throws {
        let source = """
        class MyViewModel {
            init(client: APIClient) { }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.count == 1)
        #expect(concreteIssues[0].message.contains("APIClient"))
    }

    // MARK: - Stored property without initializer

    @Test func testDetectsConcreteTypeInStoredProperty() throws {
        let source = """
        class MyViewModel {
            var repo: UserRepository
            init(repo: UserRepository) { self.repo = repo }
        }
        """
        let issues = analyzeSource(source)
        // The stored property `var repo: UserRepository` (no initializer) should fire.
        // The init parameter also fires.
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.count >= 1)
        #expect(concreteIssues.contains { $0.message.contains("UserRepository") })
    }

    // MARK: - Optional concrete type

    @Test func testDetectsOptionalConcreteType() throws {
        let source = """
        class Owner {
            var repo: UserRepository?
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.count == 1)
        #expect(concreteIssues[0].message.contains("UserRepository"))
    }

    // MARK: - Protocol-named type — no issue

    @Test func testNoIssueForProtocolNamedType() throws {
        let source = """
        class Owner {
            var service: NetworkServiceProtocol
            init(service: NetworkServiceProtocol) { self.service = service }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.isEmpty)
    }

    // MARK: - Property wrapper — no issue

    @Test func testNoIssueForPropertyWrapperProperty() throws {
        let source = """
        import SwiftUI
        struct MyView: View {
            @ObservedObject var vm: MyViewModel
            var body: some View { Text("") }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.isEmpty)
    }

    // MARK: - Non-matching suffix — no issue

    @Test func testNoIssueForNonServiceSuffix() throws {
        let source = """
        class Owner {
            func foo(counter: PageCounter) { }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        // "PageCounter" does not end with any ServiceSuffix
        #expect(concreteIssues.isEmpty)
    }

    // MARK: - Non-service value type param — no issue

    @Test func testNoIssueForValueTypeParam() throws {
        let source = """
        class Owner {
            func setup(config: AppConfiguration) { }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        // "AppConfiguration" has no matching suffix
        #expect(concreteIssues.isEmpty)
    }

    // MARK: - Multiple concrete type usages

    @Test func testDetectsMultipleConcreteTypeUsages() throws {
        let source = """
        class Setup {
            func configure(api: APIService, repo: UserRepository) { }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.count == 2)
    }

    // MARK: - Opaque some Protocol — no issue

    @Test func testNoIssueForSomeProtocol() throws {
        let source = """
        class Owner {
            func foo(service: some NetworkProtocol) { }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.isEmpty)
    }
}

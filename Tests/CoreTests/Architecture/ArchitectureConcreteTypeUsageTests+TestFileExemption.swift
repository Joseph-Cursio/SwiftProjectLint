@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

extension ArchitectureConcreteTypeUsageTests {
    // MARK: - Test file exemption

    @Test func testNoIssueInTestFiles() {
        let source = """
        class Setup {
            func configure(service: APIService) { }
        }
        """
        let issues = analyzeSource(source, filePath: "SetupTests.swift")
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.isEmpty)
    }

    // MARK: - Mock type exemption

    @Test func testNoIssueForMockTypes() {
        let source = """
        class Owner {
            var storage: MockViolationStorageForViewModel
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.isEmpty)
    }

    // MARK: - SwiftUI View + ViewModel exemption

    @Test func testNoIssueForViewModelInSwiftUIView() {
        let source = """
        struct RuleBrowserView: View {
            var viewModel: RuleBrowserViewModel
            var body: some View { Text("") }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.isEmpty)
    }

    @Test func testNoIssueForViewModelParamInSwiftUIView() {
        let source = """
        struct DetailView: View {
            init(viewModel: RuleDetailViewModel) { }
            var body: some View { Text("") }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.isEmpty)
    }

    @Test func testNoIssueForAnyServiceTypeInSwiftUIView() {
        let source = """
        struct OnboardingView: View {
            var onboardingManager: OnboardingManager
            var workspaceManager: WorkspaceManager
            var body: some View { Text("") }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.isEmpty)
    }

    // MARK: - Still detects real violations

    @Test func testStillDetectsConcreteServiceInNonView() {
        let source = """
        class Coordinator {
            var service: APIService
            init(service: APIService) { self.service = service }
        }
        """
        let issues = analyzeSource(source, filePath: "Coordinator.swift")
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.count >= 1)
    }

    // MARK: - Behaviour-type suffixes (Runner, Indexer, ...)

    @Test func testDetectsRunnerSuffixProperty() throws {
        // A concrete `Runner`-typed dependency injected into a type is exactly the
        // testability seam this rule targets; `Runner` was previously absent from the
        // service-type suffix set, so it slipped through.
        let source = """
        final class Reflector {
            private let buildRunner: BuildRunner
            init(buildRunner: BuildRunner) { self.buildRunner = buildRunner }
        }
        """
        let issues = analyzeSource(source, filePath: "Reflector.swift")
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        let issue = try #require(concreteIssues.first)
        #expect(issue.message.contains("BuildRunner"))
        #expect(issue.message.contains("buildRunner"))
    }

    @Test func testServiceTypeSuffixMatchesNewBehaviourSuffixes() {
        // Lock the newly added suffixes so the set cannot silently regress.
        #expect(ServiceTypeSuffix.matches("BuildRunner"))
        #expect(ServiceTypeSuffix.matches("WorkspaceIndexer"))
        #expect(ServiceTypeSuffix.matches("DocCFetcher"))
        #expect(ServiceTypeSuffix.matches("FileSystemWatcher"))
        #expect(ServiceTypeSuffix.matches("BuildErrorInterpreter"))
        #expect(ServiceTypeSuffix.matches("PlainValue") == false)
    }
}

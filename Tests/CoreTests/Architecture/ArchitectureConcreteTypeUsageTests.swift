@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ArchitectureConcreteTypeUsageTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "SourceFile.swift"
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
        let issue = try #require(concreteIssues.first)
        #expect(issue.message.contains("APIService"))
        #expect(issue.message.contains("service"))
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
        let issue = try #require(concreteIssues.first)
        #expect(issue.message.contains("APIClient"))
    }

    // MARK: - Stored property without initializer

    @Test func testDetectsConcreteTypeInStoredProperty() {
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
        let issue = try #require(concreteIssues.first)
        #expect(issue.message.contains("UserRepository"))
    }

    // MARK: - Protocol-named type — no issue

    @Test func testNoIssueForProtocolNamedType() {
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

    @Test func testNoIssueForPropertyWrapperProperty() {
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

    @Test func testNoIssueForNonServiceSuffix() {
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

    // MARK: - Extended service suffixes (Analyzer / Simulator / Engine / Checker)

    @Test func testDetectsAnalyzerAndSimulatorSuffixes() {
        let source = """
        class ViewModel {
            var workspaceAnalyzer: WorkspaceAnalyzer?
            var simulator: ImpactSimulator?
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.contains { $0.message.contains("WorkspaceAnalyzer") })
        #expect(concreteIssues.contains { $0.message.contains("ImpactSimulator") })
    }

    @Test func testDetectsEngineAndCheckerSuffixes() {
        let source = """
        class Owner {
            func run(engine: YAMLConfigurationEngine, checker: VersionChecker) { }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.contains { $0.message.contains("YAMLConfigurationEngine") })
        #expect(concreteIssues.contains { $0.message.contains("VersionChecker") })
    }

    // MARK: - Non-service value type param — no issue

    @Test func testNoIssueForValueTypeParam() {
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

    @Test func testDetectsMultipleConcreteTypeUsages() {
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

    @Test func testNoIssueForSomeProtocol() {
        let source = """
        class Owner {
            func foo(service: some NetworkProtocol) { }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.isEmpty)
    }

    // MARK: - DI container exemption

    @Test func testNoIssueInsideDIContainer() {
        let source = """
        class DependencyContainer {
            var workspaceManager: WorkspaceManager
            var onboardingManager: OnboardingManager
            init(workspaceManager: WorkspaceManager, onboardingManager: OnboardingManager) {
                self.workspaceManager = workspaceManager
                self.onboardingManager = onboardingManager
            }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.isEmpty)
    }

    // MARK: - System type exemption

    @Test func testNoIssueForSystemTypes() {
        let source = """
        class Analyzer {
            var fileManager: FileManager
            init(fileManager: FileManager) { self.fileManager = fileManager }
        }
        """
        let issues = analyzeSource(source)
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.isEmpty)
    }

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
}

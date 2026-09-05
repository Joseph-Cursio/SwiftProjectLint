@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Drives `ConcreteTypeUsageVisitor` over `source` and returns its findings.
///
/// At file scope rather than inside the suite: it is the suite's only helper, and keeping it out
/// of the type keeps the body within `type_body_length` as tests accumulate. Call sites read
/// identically either way.
///
/// `observableTypes` and `protocolTypes` are the project-wide prescan results `ProjectLinter`
/// injects in a real run, so the `@Observable`/`ObservableObject` and "type is already a protocol"
/// exemptions can be exercised at the visitor level. They were three overloads that differed only
/// in which one they set; defaulting both to empty says the same thing once.
private func analyzeSource(
    _ source: String,
    observableTypes: Set<String> = [],
    protocolTypes: Set<String> = [],
    functionTypeAliases: Set<String> = [],
    filePath: String = "SourceFile.swift"
) -> [LintIssue] {
    let visitor = ConcreteTypeUsageVisitor(patternCategory: .architecture)
    visitor.knownObservableTypes = observableTypes
    visitor.knownProtocolTypes = protocolTypes
    visitor.knownFunctionTypeAliases = functionTypeAliases
    let syntax = Parser.parse(source: source)
    let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
    visitor.setSourceLocationConverter(converter)
    visitor.setFilePath(filePath)
    visitor.walk(syntax)
    return visitor.detectedIssues
}

@Suite
struct ArchitectureConcreteTypeUsageTests {

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

    // MARK: - @Observable exemption

    /// A property typed as a project `@Observable`/`ObservableObject` model must not be
    /// nudged toward a protocol — hiding it behind `any P` severs SwiftUI observation.
    @Test func testNoIssueForObservableTypedProperty() {
        let source = """
        final class Coordinator {
            var session: SessionStore
            init(session: SessionStore) { self.session = session }
        }
        """
        let issues = analyzeSource(source, observableTypes: ["SessionStore"])
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.isEmpty)
    }

    /// Control: the same `…Store` name with no observable prescan entry is still flagged,
    /// proving the exemption — not the suffix — is what suppresses the observable case.
    @Test func testFlagsSameTypeWhenNotObservable() {
        let source = """
        final class Coordinator {
            var session: SessionStore
            init(session: SessionStore) { self.session = session }
        }
        """
        let issues = analyzeSource(source, observableTypes: [])
        let concreteIssues = issues.filter { $0.ruleName == .concreteTypeUsage }
        #expect(concreteIssues.contains { $0.message.contains("SessionStore") })
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

    // MARK: - Known-protocol exemption (bare existentials)

    @Test func testNoIssueForKnownProtocolUsedAsBareExistential() {
        // `ResourceMetricsProvider` is a protocol whose name does not end in
        // Protocol/Type/Interface; used as a bare existential it must not be flagged
        // once the project-wide protocol prescan recognises it as already-abstract.
        let source = """
        final class ResourceGovernor {
            private let provider: ResourceMetricsProvider
            init(provider: ResourceMetricsProvider) { self.provider = provider }
        }
        """
        let issues = analyzeSource(
            source, protocolTypes: ["ResourceMetricsProvider"], filePath: "ResourceGovernor.swift"
        ).filter { $0.ruleName == .concreteTypeUsage }
        #expect(issues.isEmpty)
    }

    @Test func testFlagsSameTypeWhenNotKnownProtocol() throws {
        // Control: with no protocol prescan the same property is flagged — proving the
        // prescan, not some unrelated exemption, is what suppresses the false positive.
        let source = """
        final class ResourceGovernor {
            private let provider: ResourceMetricsProvider
            init(provider: ResourceMetricsProvider) { self.provider = provider }
        }
        """
        let issues = analyzeSource(source, filePath: "ResourceGovernor.swift")
            .filter { $0.ruleName == .concreteTypeUsage }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("ResourceMetricsProvider"))
    }

    // MARK: - A closure typealias is already the seam

    // `CLIToolCommandRunner = @Sendable ([String], Data?) async throws -> (Data, Data, Int32)`
    // is a function type. A property typed with it is injected by handing in another closure,
    // which is exactly what a test does — asking for "a protocol abstraction" around it swaps a
    // working seam for a heavier one. Reported against LintStudioUI's `CLIToolActor`.

    @Test
    func closureTypeAliasPropertyIsNotFlagged() {
        let issues = analyzeSource("""
        final class CLIToolActor {
            private let commandRunner: CLIToolCommandRunner?
        }
        """, functionTypeAliases: ["CLIToolCommandRunner"])
        #expect(issues.isEmpty)
    }

    @Test
    func closureTypeAliasParameterIsNotFlagged() {
        let issues = analyzeSource("""
        final class CLIToolActor {
            init(commandRunner: CLIToolCommandRunner? = nil) {}
        }
        """, functionTypeAliases: ["CLIToolCommandRunner"])
        #expect(issues.isEmpty)
    }

    @Test
    func aRealServiceTypeIsStillFlagged() {
        // The control. Without it this change could silence the rule entirely and the suite
        // would not notice — the catalog is empty in most tests.
        let issues = analyzeSource("""
        final class Client {
            private let networkService: NetworkService?
        }
        """, functionTypeAliases: ["CLIToolCommandRunner"])
        #expect(issues.isEmpty == false)
    }


    // MARK: - A generic type is already parameterised

    // `Generator<[Element], Shrinker>` cannot usefully take the advice: `any GeneratorProtocol`
    // erases the element type and the shrinker, which is the whole of what the type carries.
    // Measured on SwiftPropertyLaws, where every law takes a generator — 215 of its 218 findings
    // named `Generator`, and 263 of 267 uses there carry generic arguments.

    @Test
    func genericParameterIsNotFlagged() {
        let issues = analyzeSource("""
        func checkLaw<Element, Shrinker>(generator: Generator<[Element], Shrinker>) {}
        """)
        #expect(issues.isEmpty)
    }

    @Test
    func genericPropertyIsNotFlagged() {
        let issues = analyzeSource("""
        struct LawRunner {
            private let generator: Generator<Int, AnySequence<Int>>
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test
    func optionalGenericIsNotFlagged() {
        let issues = analyzeSource("""
        struct LawRunner {
            private let generator: Generator<Int, AnySequence<Int>>?
        }
        """)
        #expect(issues.isEmpty)
    }

    @Test
    func aBareServiceTypeIsStillFlaggedWithoutGenerics() {
        // The control. A foreign service taking no parameters — `Alamofire.Session` in the
        // motivating shape — can be wrapped behind your own protocol, and that is the canonical
        // advice. Without this the exemption could be silencing the rule outright.
        let issues = analyzeSource("""
        struct Client {
            private let networkService: NetworkService
        }
        """)
        #expect(issues.isEmpty == false)
    }

}

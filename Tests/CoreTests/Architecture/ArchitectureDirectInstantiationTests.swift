@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct ArchitectureDirectInstantiationTests {

    // MARK: - Helper

    private func analyzeSource(
        _ source: String,
        filePath: String = "TestFile.swift"
    ) -> [LintIssue] {
        let visitor = DirectInstantiationVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues
    }

    // MARK: - Stored property

    @Test func testDetectsDirectInstantiationInStoredProperty() throws {
        let source = """
        class MyView {
            private let svc = NetworkService()
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        let issue = try #require(directIssues.first)
        #expect(issue.message.contains("NetworkService"))
    }

    // MARK: - Constructor default

    @Test func testDetectsDirectInstantiationInConstructorDefault() throws {
        let source = """
        class MyViewModel {
            init(svc: NetworkService = NetworkService()) { }
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        let issue = try #require(directIssues.first)
        #expect(issue.message.contains("NetworkService"))
    }

    // MARK: - Function body

    @Test func testDetectsDirectInstantiationInFunctionBody() throws {
        let source = """
        class Setup {
            func setup() {
                let svc = NetworkService()
                _ = svc
            }
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        let issue = try #require(directIssues.first)
        #expect(issue.message.contains("NetworkService"))
    }

    // MARK: - Closure

    @Test func testDetectsDirectInstantiationInClosure() throws {
        let source = """
        class Owner {
            var fn: () -> Void = {
                let repo = UserRepository()
                _ = repo
            }
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        let issue = try #require(directIssues.first)
        #expect(issue.message.contains("UserRepository"))
    }

    // MARK: - No issue for injected dependency

    @Test func testNoIssueForInjectedDependency() {
        let source = """
        class MyViewModel {
            private let service: NetworkService
            init(service: NetworkService) {
                self.service = service
            }
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.isEmpty)
    }

    // MARK: - No issue for property wrapper instantiation

    @Test func testNoIssueForPropertyWrapperInstantiation() {
        let source = """
        import SwiftUI
        struct MyView: View {
            @StateObject private var vm = MyViewModel()
            var body: some View { Text("") }
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.isEmpty)
    }

    // MARK: - No issue for non-matching types

    @Test func testNoIssueForValueTypes() {
        let source = """
        class Owner {
            let counter = Counter()
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.isEmpty)
    }

    // MARK: - Multiple instantiations

    @Test func testDetectsMultipleInstantiations() {
        let source = """
        class Owner {
            let apiClient = APIClient()
            let dataStore = UserDataStore()
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.count == 2)
    }

    // MARK: - Singleton definition site (self-instantiation) is exempt

    @Test func testNoIssueForStaticSharedSelfInstantiation() {
        // `static let shared = ProjectParser()` inside `ProjectParser` is the
        // canonical singleton definition, not an injectable dependency.
        let source = """
        final class ProjectParser {
            static let shared = ProjectParser()
            private init() {}
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.isEmpty)
    }

    @Test func testNoIssueForStaticSelfInstantiationInStructAndActor() {
        // Applies to any nominal type vending an instance of itself statically.
        let source = """
        struct ConfigStore {
            static let shared = ConfigStore()
        }
        actor SyncEngine {
            static let shared = SyncEngine()
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        #expect(directIssues.isEmpty)
    }

    @Test func testStillFlagsStaticInstantiationOfDifferentType() throws {
        // A static member instantiating a *different* service type is still a
        // hard-coded dependency — only self-instantiation is exempt.
        let source = """
        enum Dependencies {
            static let client = APIClient()
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        let issue = try #require(directIssues.first)
        #expect(issue.message.contains("APIClient"))
    }

    @Test func testStillFlagsInstanceMemberOfSameType() throws {
        // A non-static stored property instantiating the enclosing type is not
        // the singleton idiom — keep flagging it.
        let source = """
        final class DataManager {
            let backup = DataManager()
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        let issue = try #require(directIssues.first)
        #expect(issue.message.contains("DataManager"))
    }

    // MARK: - Service-suffix coverage (regression for ServiceSuffix divergence)

    /// `Analyzer`/`Simulator`/`Engine`/`Checker` were added to the canonical
    /// suffix set in `ConcreteTypeUsage` but never propagated to the other
    /// architecture rules, which each held a private copy. After consolidating
    /// onto `ServiceTypeSuffix`, this rule must detect them too.
    @Test("Detects direct instantiation of newly-restored service suffixes", arguments: [
        "PaymentEngine", "RiskAnalyzer", "FlightSimulator", "SpellChecker"
    ])
    func testDetectsRestoredServiceSuffixes(typeName: String) throws {
        let source = """
        class Owner {
            let dependency = \(typeName)()
        }
        """
        let issues = analyzeSource(source)
        let directIssues = issues.filter { $0.ruleName == .directInstantiation }
        let issue = try #require(directIssues.first)
        #expect(issue.message.contains(typeName))
    }
}

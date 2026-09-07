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

    @Test func testDefaultedParameterIsASeamNotAViolation() {
        // A defaulted parameter *is* the injection point: a test substitutes by passing one,
        // which is the whole requirement. The old advice — "remove the default value and
        // inject at the call site" — makes every caller construct one for no testability gain.
        //
        // The rule was also inconsistent about it. Three defaults hard-wire production
        // identically and only the constructor spelling was reported:
        //
        //     init(svc: NetworkService = NetworkService())   // flagged
        //     init(svc: NetworkService = .shared)            // silent
        //     init(fm: FileManager = .default)               // silent
        //
        // If the concern is the hard-wire, `.shared` is the worse case. The line was drawn on
        // syntax rather than substance, and `= .default` is the convention these projects use.
        let source = """
        class MyViewModel {
            init(svc: NetworkService = NetworkService()) { }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testStoredPropertyHardWireIsStillDetected() throws {
        // The control, and where the rule's value actually is. A stored property with an
        // inline initializer has no seam at all — there is no parameter to pass.
        let source = """
        class MyViewModel {
            private let svc = NetworkService()
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
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

    // MARK: - Callee must name a type

    @Test func testStaticMemberCallIsNotAnInstantiation() {
        // `DerivationStrategist.composedGenerator(forTypeName:)` is a `static func` returning a
        // value. The suffix test used to run against the whole callee text, so the *member's*
        // name ending in "Generator" was read as a type name and the finding read "direct
        // instantiation of 'DerivationStrategist.composedGenerator' — prefer dependency
        // injection", naming something that does not exist and cannot be injected.
        let source = """
        func resolve() {
            let result = DerivationStrategist.composedGenerator(forTypeName: name)
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testModuleQualifiedConstructionIsStillReported() throws {
        // The other half of the same change: dropping every member access would go too far,
        // because `Module.Type()` is an ordinary construction written with a qualifier.
        let source = """
        func boot() {
            let svc = Networking.NetworkService()
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("NetworkService"))
    }

    @Test func testGenericSpecializationIsStillReported() throws {
        let source = """
        func boot() {
            let svc = NetworkService<Int>()
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("NetworkService"))
    }

    // MARK: - File-local types cannot be injected

    @Test func testPrivateTypeIsNotReported() {
        // A `private` type is unreachable outside the file that declares it, so there is no
        // caller that could supply a substitute. Taking the advice would mean widening the
        // access level in order to hide the type — exporting an implementation detail to make
        // it injectable.
        let source = """
        enum AmbientStateReads {
            static func occur(in node: Syntax) -> Bool {
                let checker = Checker(viewMode: .sourceAccurate)
                checker.walk(node)
                return checker.sawSource
            }

            private final class Checker: SyntaxVisitor {
                var sawSource = false
            }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testFileprivateTypeIsNotReported() {
        let source = """
        func isTotal(_ syntax: Syntax) -> Bool {
            let checker = TotalityChecker()
            checker.walk(syntax)
            return checker.isTotal
        }

        fileprivate final class TotalityChecker: SyntaxVisitor {
            var isTotal = true
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testDeclarationAfterUseIsStillSeen() {
        // The reason the access level is read in a pre-pass rather than as the walk goes: the
        // construction usually comes first. `AmbientStateReads.occur` builds its `Checker`
        // eight lines above the `private final class Checker` that declares it.
        let source = """
        func query(_ node: Syntax) -> Bool {
            let checker = LocalChecker()
            return checker.result
        }

        private final class LocalChecker {
            var result = false
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testNonPrivateTypeInTheSameFileIsStillReported() throws {
        // The gate is about reachability, not about locality. An `internal` type declared in
        // the same file *can* be named — and substituted — by any other file in the module.
        let source = """
        func query(_ node: Syntax) -> Bool {
            let checker = SharedChecker()
            return checker.result
        }

        final class SharedChecker {
            var result = false
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("SharedChecker"))
    }

    // MARK: - Test doubles

    @Test func testMockTypeIsNotReported() {
        // A double is already the substitute an injection would supply. `ConcreteTypeUsage` —
        // the rule that counts the same seam from the declaration end — has exempted these
        // since its own correction; this rule never had the vocabulary, so `MockGenerator` was
        // exempt where it was declared and reported where it was built.
        let source = """
        func lift() {
            let generator = MockGenerator(typeName: name)
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }
}

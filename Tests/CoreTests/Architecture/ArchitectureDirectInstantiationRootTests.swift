@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// `Direct Instantiation`\'s composition-root gate, in its own suite because the shape needs
/// whole assembler bodies to exercise and the main suite was over the type-body length limit.
@Suite
struct ArchitectureDirectInstantiationRootTests {

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

    @Test func testCompositionRootIsNotReported() {
        // Dependency injection has to bottom out. A body that wires three or more concrete
        // services and *keeps* them is the one place allowed to know every concrete type;
        // reporting each construction turns one architectural fact into a warning per line.
        let source = """
        final class AppState {
            var chatSessionStore: ChatSessionStore?
            var skillLocalStore: SkillLocalStore?
            var swiftLintRunner: SwiftLintRunner?

            func constructCoreServices() {
                let chatSessionStore = ChatSessionStore()
                let localStore = SkillLocalStore()
                let runner = SwiftLintRunner()
                self.chatSessionStore = chatSessionStore
                self.skillLocalStore = localStore
                self.swiftLintRunner = runner
            }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testBareAssignmentToAStoredPropertyCountsAsRetention() {
        // `handler = newHandler` inside `ExtensionServiceContainer` and
        // `workspaceIndexer = indexer` inside an `AppState` extension both assign to a stored
        // property without writing `self.`. Told apart from a local by name.
        let source = """
        actor ServiceContainer {
            var handler: EditorCommandHandler?

            func commandHandler() {
                let runner = SwiftLintRunner()
                let reflection = LintReflectionRunner(lintRunner: runner)
                let newHandler = EditorCommandHandler(reflection: reflection)
                handler = newHandler
            }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testDispatcherThatKeepsNothingIsStillReported() {
        // The reason the gate is not a neighbour count. `ProjectAnalyzer.analyze(paths:)`
        // builds four diagram generators, uses each once and returns a summary. Under the
        // count alone it went silent while an identical `ClassDiagramGenerator()` forty lines
        // below, in a function with fewer neighbours, kept reporting — the same construction
        // answered two ways depending on its siblings.
        let source = """
        enum ProjectAnalyzer {
            static func analyze(paths: [String]) -> Summary {
                let generator = ClassDiagramGenerator()
                let deps = DependencyGraphGenerator()
                let states = StateMachineGenerator()
                return Summary(
                    types: generator.analyzeTypes(for: paths),
                    edges: deps.extractEdges(for: paths),
                    machines: states.findCandidates(for: paths)
                )
            }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.count == 3)
    }

    @Test func testTwoServicesIsNotARoot() {
        // At a threshold of two, the ordinary case the rule exists to catch — a function
        // reaching for a store and its index — would go silent.
        let source = """
        final class Loader {
            var store: PaymentStore?

            func load() {
                let store = PaymentStore()
                let indexer = CorpusIndexer()
                self.store = store
                _ = indexer
            }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.count == 2)
    }

    @Test func testLocalReassignmentIsNotRetention() {
        // A body that assigns only to its own locals keeps nothing. Every `let`/`var` the body
        // binds is collected, and a target inside that set does not count.
        let source = """
        func build() -> Report {
            var runner = SwiftLintRunner()
            let formatter = SwiftFormatRunner()
            let parser = SwiftLintConfigParser()
            runner = SwiftLintRunner()
            return Report(runner: runner, formatter: formatter, parser: parser)
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.count == 3)
    }

    // MARK: - The program entry point

    @Test func testTopLevelCodeInMainSwiftIsNotReported() {
        // `main.swift` holds top-level code, which Swift permits in no other file: it *is* the
        // program. There is nowhere further out to push a construction.
        let source = """
        let store = PaymentStore()

        let runtime = LambdaRuntime { event, context in
            try await handleSQSBatch(event, store: store)
        }
        """
        let issues = analyzeSource(source, filePath: "main.swift")
            .filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testTheSameCodeInAnotherFileIsReported() throws {
        let source = """
        let store = PaymentStore()
        """
        let issues = analyzeSource(source, filePath: "Boot.swift")
            .filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("PaymentStore"))
    }

    @Test func testStaticMainOfAMainTypeIsNotReported() {
        let source = """
        @main
        struct SpikeApp {
            static func main() async throws {
                let store = PaymentStore()
                let profiles = ProfileStore()
                try await Application(store: store, profiles: profiles).run()
            }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testInitOfAMainAppIsNotReported() {
        // A SwiftUI `App`'s `init()` seeds the containers the whole program reads from — the
        // same role `static func main()` plays for a command-line `@main`.
        let source = """
        @main
        struct StudioApp: App {
            @State private var registry: RuleRegistry

            init() {
                let cacheManager = CacheManager()
                _registry = State(initialValue: RuleRegistry(cacheManager: cacheManager))
            }

            var body: some Scene { WindowGroup { ContentView() } }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testOtherMembersOfAMainTypeAreStillReported() throws {
        // The gate is the entry point, not the whole type. A `@main` type's other methods
        // are ordinary code and hard-wiring a dependency in one is an ordinary finding.
        let source = """
        @main
        struct StudioApp: App {
            static func main() { StudioApp.main() }

            func refresh() {
                let manager = CacheManager()
                _ = manager
            }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("CacheManager"))
    }

    @Test func testStaticMainWithoutTheMainAttributeIsStillReported() throws {
        let source = """
        struct NotTheEntryPoint {
            static func main() {
                let store = PaymentStore()
                _ = store
            }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("PaymentStore"))
    }

    // MARK: - Helpers handed their own owner

    @Test func testHelperConstructedWithSelfIsNotReported() {
        // `self` does not exist before the initializer that would receive a substitute has
        // run, so the advice needs two-phase initialization to buy a substitution nobody can
        // use — the helper is bound to this owner anyway.
        let source = """
        class AccessibilityVisitor {
            private lazy var buttonChecker = ButtonAccessibilityChecker(visitor: self)
            private lazy var imageChecker = ImageAccessibilityChecker(visitor: self)
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testAnOrdinaryArgumentIsStillReported() throws {
        let source = """
        class Loader {
            private let runner = SwiftLintRunner(configPath: configPath)
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        let issue = try #require(issues.first)
        #expect(issue.message.contains("SwiftLintRunner"))
    }

    // MARK: - Types the runtime constructs

    @Test func testParsableCommandIsNotReported() {
        // ArgumentParser builds a command out of argv and calls `run()`. The synthesized
        // initializer takes only the decoded `@Option`/`@Argument`/`@Flag` values, so there is
        // no parameter for a dependency — and the one remaining spelling, a stored property
        // with an inline default, is the shape this rule reports. Every form of the fix is
        // either impossible or itself a finding.
        let source = """
        struct IndexCodeCommand: AsyncParsableCommand {
            @Option var path: String?

            func run() async throws {
                let indexer = CorpusIndexer(backend: OllamaBackend())
                try await indexer.index(path: path)
            }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testCommandHelpersAreCoveredToo() {
        // Not only `run()`. `BootstrapSkillsCommand.makeDetector()` assembles a registry, an
        // anti-pattern store, a knowledge graph and a builder in a private helper; the
        // constraint that makes the advice unreachable belongs to the command type, not to one
        // of its methods.
        let source = """
        struct BootstrapSkillsCommand: AsyncParsableCommand {
            func run() async throws { _ = try await makeDetector() }

            private func makeDetector() async throws -> SkillGapDetector {
                let antiPatternStore = AntiPatternStore()
                await antiPatternStore.loadLoggingFailures()
                return SkillGapDetector(store: antiPatternStore)
            }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.isEmpty)
    }

    @Test func testAnOrdinaryTypeInTheSameFileIsStillReported() throws {
        let source = """
        struct IndexCodeCommand: AsyncParsableCommand {
            func run() async throws {
                let indexer = CorpusIndexer()
                _ = indexer
            }
        }

        struct Helper {
            func work() {
                let indexer = CorpusIndexer()
                _ = indexer
            }
        }
        """
        let issues = analyzeSource(source).filter { $0.ruleName == .directInstantiation }
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("CorpusIndexer"))
    }
}

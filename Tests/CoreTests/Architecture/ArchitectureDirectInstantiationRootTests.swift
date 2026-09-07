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
}

@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Assigning a closure literal to a binding proves its declared type is a function type — the
/// compiler would reject it otherwise. That is what lets `ConcreteTypeUsage` recognise a seam whose
/// `typealias` is declared in a package this project does not own.
@Suite("A closure assignment proves the declared type is a function type")
struct ClosureAssignmentEvidenceTests {

    private func names(_ source: String) -> Set<String> {
        let collector = FunctionTypeAliasCollector()
        collector.walk(Parser.parse(source: source))
        return collector.collectedTypes
    }

    /// The corpus shape, from `SwiftLintCLIActor.init` and `SwiftFormatCLIActor.init`.
    /// `CLIToolCommandRunner` is declared in LintStudioUI — a different repository — so the alias
    /// scan cannot reach it, and both repositories reported a finding nobody could act on.
    @Test func aDeferredAssignmentProvesTheType() {
        let source = """
        actor Tool {
            init(commandRunner: Runner?) {
                var bridgedRunner: CLIToolCommandRunner?
                if let commandRunner {
                    bridgedRunner = { arguments, _ in try await commandRunner(arguments) }
                }
                self.tool = CLIToolActor(runner: bridgedRunner)
            }
        }
        """
        #expect(names(source).contains("CLIToolCommandRunner"))
    }

    @Test func anInitialisedDeclarationProvesTheType() {
        let source = """
        func make() {
            let runner: ForeignRunner = { _ in Data() }
            use(runner)
        }
        """
        #expect(names(source).contains("ForeignRunner"))
    }

    /// The alias path still works on its own, and an alias in scope needs no assignment.
    @Test func theAliasPathIsUnaffected() {
        let source = "typealias Runner = @Sendable ([String]) async throws -> Data"
        #expect(names(source) == ["Runner"])
    }

    // MARK: - What it must not claim

    /// A service assigned from a call is not a function type, and this is the shape the gate would
    /// wrongly exempt if it keyed on assignment alone rather than on the assigned *value*.
    @Test func assigningACallResultProvesNothing() {
        let source = """
        func make() {
            var client: OllamaHTTPClient?
            client = OllamaHTTPClient(baseURL: url)
            use(client)
        }
        """
        #expect(names(source).isEmpty)
    }

    /// A closure assigned to a *property* of something else says nothing about the local's type.
    @Test func assigningThroughAMemberProvesNothing() {
        let source = """
        func make() {
            var holder: SomeService?
            holder?.handler = { _ in }
            use(holder)
        }
        """
        #expect(names(source).isEmpty)
    }

    /// The declaration and the assignment must share a body. Without that, any name reused across
    /// two functions could lend its type to a closure it has nothing to do with.
    @Test func aDeclarationInAnotherBodyIsNotEvidence() {
        let source = """
        func declare() {
            var runner: RealService?
            use(runner)
        }
        func assign() {
            var runner: Callback?
            runner = { _ in }
            use(runner)
        }
        """
        #expect(!names(source).contains("RealService"))
        #expect(names(source).contains("Callback"))
    }

    /// No annotation, nothing to record — the type is inferred and the collector reads spellings.
    @Test func anInferredBindingIsNotEvidence() {
        #expect(names("func make() { var handler = { _ in }; use(handler) }").isEmpty)
    }
}

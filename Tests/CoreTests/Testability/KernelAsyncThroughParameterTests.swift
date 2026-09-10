import Foundation
import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// `declaredAsync` is a refutation about the *signature*. The oracle stops there rather than
/// reading the body, which is right for the question it is asked and wrong for the question this
/// catalog asks — **does the type hold anything a test could not supply?**
@Suite("A kernel may await something it was handed")
struct KernelAsyncThroughParameterTests {

    private func catalog(_ source: String) -> CleanInstanceMethodCatalog {
        CleanInstanceMethodCatalog.build(from: [Parser.parse(source: source)], enumTypes: [])
    }

    /// The corpus shape. `BuildErrorInterpreter` has no stored properties and awaits the caller's
    /// collaborator; refusing it made two rules ask for a protocol in front of a type whose every
    /// input is already a parameter.
    @Test func awaitingAParameterIsStillAKernel() {
        let source = """
        struct Interpreter {
            func interpret(text: String, graph: KnowledgeGraph) async throws -> Result {
                let found = try await graph.skills.provenance(for: text)
                return Result(found)
            }
        }
        """
        #expect(catalog(source).isPureKernel("Interpreter"))
    }

    // MARK: - What it must still refuse

    /// Zero storage is not the gate, and this is why. Nothing about `Purger` is held and nothing
    /// about it is controllable: no argument reaches `globalCoordinator`.
    @Test func awaitingAGlobalIsNotAKernel() {
        let source = """
        struct Purger {
            func purge(_ path: URL) async { await globalCoordinator.delete(path) }
        }
        """
        #expect(!catalog(source).isPureKernel("Purger"))
    }

    /// Both halves are required. `declaredAsync` is reported *before* the marker scan runs, so the
    /// parameter check alone would admit a method that also reaches the file system — which is why
    /// the method is re-asked with `async` stripped.
    @Test func awaitingAParameterWhileTouchingTheFileSystemIsNotAKernel() {
        let source = """
        struct Mixed {
            func run(_ path: URL, graph: KnowledgeGraph) async throws {
                _ = try await graph.load()
                try FileManager.default.removeItem(at: path)
            }
        }
        """
        #expect(!catalog(source).isPureKernel("Mixed"))
    }

    /// A marker with no `try` or `await` on it at all. `declaredAsync` is reported from the
    /// signature, so the oracle never reaches the `print`, and a parameter-rooted-await check on its
    /// own would admit this.
    @Test func awaitingAParameterWhileAlsoPrintingIsNotAKernel() {
        let source = """
        struct Chatty {
            func run(graph: KnowledgeGraph) async throws {
                print("starting")
                _ = try await graph.load()
            }
        }
        """
        #expect(!catalog(source).isPureKernel("Chatty"))
    }

    /// An await on `self` is a sibling call, which `SelfAccessAnalyzer` already judges against the
    /// clean set. Following it here as well would be a second, weaker answer to the same question.
    @Test func awaitingSelfIsNotAKernel() {
        let source = """
        struct Chained {
            func outer(_ text: String) async -> String { await inner(text) }
            func inner(_ text: String) async -> String { text }
        }
        """
        #expect(!catalog(source).isPureKernel("Chained"))
    }

    /// A local that merely *came from* a parameter does not count. Following it would be dataflow,
    /// and one missed reassignment turns a dependency into a kernel.
    @Test func awaitingALocalDerivedFromAParameterIsNotAKernel() {
        let source = """
        struct Indirect {
            func run(graph: KnowledgeGraph) async throws {
                let skills = graph.skills
                _ = try await skills.load()
            }
        }
        """
        #expect(!catalog(source).isPureKernel("Indirect"))
    }

    /// An `async` signature with nothing awaited is not a shape to reason about from here, so the
    /// verdict is left where the oracle put it.
    @Test func anAsyncMethodWithNoAwaitIsNotAKernel() {
        #expect(!catalog("struct Idle { func go(_ x: Int) async -> Int { x } }").isPureKernel("Idle"))
    }

    /// A parameterless `async` method has nothing it could have been handed.
    @Test func aParameterlessAsyncMethodIsNotAKernel() {
        let source = """
        struct Fetcher {
            func load() async throws -> Data { try await remote.fetch() }
        }
        """
        #expect(!catalog(source).isPureKernel("Fetcher"))
    }

    /// Storage still decides. An `await` on a parameter does not excuse holding a `UserDefaults`.
    @Test func storageStillDisqualifies() {
        let source = """
        struct Store {
            let defaults: UserDefaults
            func load(graph: KnowledgeGraph) async throws -> Data { try await graph.load() }
        }
        """
        #expect(!catalog(source).isPureKernel("Store"))
    }
}

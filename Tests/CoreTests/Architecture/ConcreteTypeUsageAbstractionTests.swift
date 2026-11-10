import Foundation
import SwiftProjectLintModels
import Testing

/// A type that is already abstracted is not asked for a protocol.
///
/// Three spellings of a seam that is already there: a protocol whose name gives no hint, used as
/// a bare existential; a closure typealias; and a generic type, whose parameters a protocol
/// would erase. Each exemption has a control, so a change that silences the rule outright fails.
@Suite
struct ConcreteTypeUsageAbstractionTests {

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

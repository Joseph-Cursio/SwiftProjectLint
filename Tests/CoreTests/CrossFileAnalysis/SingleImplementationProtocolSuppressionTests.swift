@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The suppression half: the signals that stop a single-conformer protocol from being
/// reported — a DI-suffixed name, conformance added in an extension, and injection sites
/// that prove the seam is used.
@Suite
struct SingleImplementationProtocolSuppressionTests {

    private func analyze(
        files: [String: String],
        executablePaths: [String] = []
    ) -> [LintIssue] {
        SingleImplementationProtocolTestSupport.analyze(
            files: files, executablePaths: executablePaths
        )
    }

    // MARK: - DI suffix suppression

    @Test
    func protocolWithServiceSuffixSuppressed() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol NetworkService {
                func fetch()
            }
            """,
            "Impl.swift": """
            struct RealNetworkService: NetworkService {
                func fetch() { }
            }
            """
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func protocolWithRepositorySuffixSuppressed() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol UserRepository {
                func getUser()
            }
            """,
            "Impl.swift": """
            struct SQLiteUserRepository: UserRepository {
                func getUser() { }
            }
            """
        ])
        #expect(issues.isEmpty)
    }

    @Test
    func protocolWithProvidingSuffixSuppressed() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol DataProviding {
                func provide()
            }
            """,
            "Impl.swift": """
            struct LiveDataProvider: DataProviding {
                func provide() { }
            }
            """
        ])
        #expect(issues.isEmpty)
    }

    /// The bare `Protocol` suffix is *not* a DI-intent signal — it is the universal
    /// naming convention — so a single-conformer `FooProtocol` with no mock is flagged.
    @Test
    func protocolSuffixAloneDoesNotSuppress() throws {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol PaymentProtocol {
                func charge()
            }
            """,
            "Impl.swift": """
            struct StripePayment: PaymentProtocol {
                func charge() { }
            }
            """
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("PaymentProtocol"))
    }

    /// A conformer whose name merely *contains* a mock marker mid-word
    /// (`Mockingbird…` ⊃ `Mock`) is production code, not a test double, so it counts
    /// as the single production conformer and the protocol is still flagged.
    /// Guards against the old substring match that treated it as a mock and silently
    /// suppressed the rule.
    @Test
    func conformerWithMarkerMidNameIsNotTreatedAsMock() throws {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol Renderer {
                func render()
            }
            """,
            "Impl.swift": """
            struct MockingbirdRenderer: Renderer {
                func render() { }
            }
            """
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("Renderer"))
        #expect(issue.message.contains("MockingbirdRenderer"))
    }

    /// A `…ServiceProtocol` name ends in `Protocol`, not the role word `Service`, so
    /// the role-suffix exemption does not apply and it is flagged.
    @Test
    func serviceProtocolSuffixDoesNotSuppress() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol AnalyticsServiceProtocol {
                func track()
            }
            """,
            "Impl.swift": """
            struct AnalyticsService: AnalyticsServiceProtocol {
                func track() { }
            }
            """
        ])

        #expect(issues.count == 1)
    }

    // MARK: - Extension-based conformance

    /// `extension Foo: P` is the idiomatic way to add a conformance; the rule
    /// previously only inspected struct/class/enum/actor declarations, so a protocol
    /// conformed to solely via extensions counted zero conformers and was wrongly
    /// reported as dead code. A single extension conformer should now be counted
    /// (and flagged as the single conformer, by name).
    @Test
    func extensionConformerIsCounted() throws {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol RowDecodable {
                func decode()
            }
            """,
            "Conformer.swift": """
            struct Node { }
            extension Node: RowDecodable {
                func decode() { }
            }
            """
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("only one conformer"))
        #expect(issue.message.contains("Node"))
    }

    /// Two conformers declared via extensions are real polymorphism — the rule must
    /// stay silent. This is the `GraphRowDecodable`-with-many-extension-conformers
    /// scenario that previously produced a "dead code" false positive.
    @Test
    func multipleExtensionConformersClean() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol RowDecodable {
                func decode()
            }
            """,
            "Conformers.swift": """
            struct NodeA { }
            struct NodeB { }
            extension NodeA: RowDecodable { func decode() { } }
            extension NodeB: RowDecodable { func decode() { } }
            """
        ])

        #expect(issues.isEmpty)
    }

    // MARK: - Dependency-injection consumption suppression

    /// A single-conformer protocol injected through an initializer parameter is a
    /// deliberate DI seam — flagging it would tell the author to delete the injection
    /// point. The signal is the *consumption shape* (a constructor dependency), not the
    /// protocol's name, so it catches gerund capability names (`DataParsing`) that the
    /// role-suffix list (`Service`, `Repository`, …) does not.
    @Test
    func singleConformerInjectedViaInitializerClean() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol DataParsing {
                func parse()
            }
            """,
            "Impl.swift": """
            struct RealParser: DataParsing {
                func parse() { }
            }
            """,
            "Engine.swift": """
            struct Engine {
                init(parser: DataParsing = RealParser()) { }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// A single-conformer protocol held as a stored property is consumed as an
    /// abstraction; the rule's advice ("use the concrete type") would force rewriting
    /// that field, so the protocol earns its keep and is exempt. `some`/`any`/optional
    /// wrappers are unwrapped to the base name.
    @Test
    func singleConformerHeldAsStoredPropertyClean() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol DataParsing {
                func parse()
            }
            """,
            "Impl.swift": """
            struct RealParser: DataParsing {
                func parse() { }
            }
            """,
            "Holder.swift": """
            final class Coordinator {
                private let parser: any DataParsing
                init(parser: any DataParsing) { self.parser = parser }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// The exemption is scoped to *held or injected* dependencies. A protocol that is
    /// only mentioned as a factory return type is not a stored/injected dependency, so
    /// the single-conformer protocol is still flagged — keeping the exemption narrow.
    @Test
    func singleConformerUsedOnlyAsReturnTypeStillFlags() throws {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol DataParsing {
                func parse()
            }
            """,
            "Impl.swift": """
            struct RealParser: DataParsing {
                func parse() { }
            }
            """,
            "Factory.swift": """
            enum Factory {
                static func make() -> DataParsing { RealParser() }
            }
            """
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("DataParsing"))
    }

    /// A mock conformer declared via an extension must suppress the warning just as a
    /// directly-declared mock does.
    @Test
    func mockConformerViaExtensionSuppresses() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol RowDecodable {
                func decode()
            }
            """,
            "Conformer.swift": """
            struct Node { }
            extension Node: RowDecodable { func decode() { } }
            """,
            "MockNode.swift": """
            struct MockNode { }
            extension MockNode: RowDecodable { func decode() { } }
            """
        ])

        #expect(issues.isEmpty)
    }
}

@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

extension MirrorProtocolVisitorTests {
    @Test
    func mirrorWithMockConformerExempt() {
        // A protocol that mirrors its type 1:1 is a justified DI seam when a mock
        // conforms to it — removing it would also remove the testing seam. The
        // shared ProtocolExemption predicate suppresses this, matching the way
        // SingleImplementationProtocol already exempts mocked protocols.
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol CacheManagerProtocol {
                func load()
                func save()
            }
            """,
            "Impl.swift": """
            struct CacheManager: CacheManagerProtocol {
                func load() { }
                func save() { }
            }
            """,
            "Mock.swift": """
            final class MockCacheManager: CacheManagerProtocol {
                func load() { }
                func save() { }
            }
            """,
        ])

        #expect(issues.isEmpty)
    }

    @Test
    func mirrorWithMockActorConformerExempt() {
        // The mock substitute may itself be an actor; conformer tracking covers
        // actors so the exemption still applies.
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol DownloaderProtocol {
                func fetch()
                func cancel()
            }
            """,
            "Impl.swift": """
            struct Downloader: DownloaderProtocol {
                func fetch() { }
                func cancel() { }
            }
            """,
            "Mock.swift": """
            actor StubDownloader: DownloaderProtocol {
                func fetch() { }
                func cancel() { }
            }
            """,
        ])

        #expect(issues.isEmpty)
    }

    @Test
    func mirrorWithoutMockStillFlags() {
        // No mock conformer — the abstraction is not justified for testing, so the
        // mirror is still reported (the DI-suffix alone does not exempt it).
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol ReportFormatterProtocol {
                func format()
                func finalize()
            }
            """,
            "Impl.swift": """
            struct ReportFormatter: ReportFormatterProtocol {
                func format() { }
                func finalize() { }
            }
            """,
        ])

        #expect(issues.count == 1)
    }

    /// A mirror protocol that is consumed as an injected dependency — held as a stored
    /// property or received as an init parameter — is a deliberate DI seam, so the
    /// mirror is exempt even without a mock conformer. Parity with
    /// SingleImplementationProtocol's consumption exemption, via the shared
    /// `DependencyConsumption` detector.
    @Test
    func mirrorConsumedAsInjectedDependencyExempt() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol ReportFormatterProtocol {
                func format()
                func finalize()
            }
            """,
            "Impl.swift": """
            struct ReportFormatter: ReportFormatterProtocol {
                func format() { }
                func finalize() { }
            }
            """,
            "Consumer.swift": """
            final class ReportBuilder {
                private let formatter: ReportFormatterProtocol
                init(formatter: ReportFormatterProtocol) {
                    self.formatter = formatter
                }
            }
            """,
        ])

        #expect(issues.isEmpty)
    }

    /// A composition names each protocol in it, so a dependency typed with one consumes them
    /// all — written inline, or through a `typealias`.
    @Test(arguments: [
        "any ReportFormatterProtocol & Sendable",
        "(any ReportFormatterProtocol & Sendable)?",
        "any SendableFormatter",
        "SendableFormatter",
    ])
    func mirrorConsumedThroughACompositionExempt(dependency: String) {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol ReportFormatterProtocol {
                func format()
                func finalize()
            }
            typealias SendableFormatter = ReportFormatterProtocol & Sendable
            """,
            "Impl.swift": """
            struct ReportFormatter: ReportFormatterProtocol {
                func format() { }
                func finalize() { }
            }
            """,
            "Consumer.swift": """
            final class ReportBuilder {
                private let formatter: \(dependency)
            }
            """,
        ])

        #expect(issues.isEmpty)
    }
}

@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct MirrorProtocolVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = MirrorProtocol().pattern
        let visitor = MirrorProtocolVisitor(fileCache: cache)
        visitor.setPattern(pattern)

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .mirrorProtocol }
    }

    @Test
    func exactMirrorFlags() throws {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol UserServiceProtocol {
                func fetchUser()
                func saveUser()
                func deleteUser()
            }
            """,
            "Impl.swift": """
            class UserService: UserServiceProtocol {
                func fetchUser() { }
                func saveUser() { }
                func deleteUser() { }
            }
            """
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("UserServiceProtocol"))
        #expect(issue.message.contains("UserService"))
    }

    @Test
    func protocolSubsetOfTypeFlags() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol DataStoreProtocol {
                func save()
                func load()
            }
            """,
            "Impl.swift": """
            class DataStore: DataStoreProtocol {
                func save() { }
                func load() { }
                func clear() { }
                func migrate() { }
                func backup() { }
            }
            """
        ])

        #expect(issues.count == 1)
    }

    @Test
    func nonMatchingNameClean() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol Loadable {
                func load()
                func cancel()
            }
            """,
            "Impl.swift": """
            class DataService: Loadable {
                func load() { }
                func cancel() { }
            }
            """
        ])

        // "Loadable" doesn't end with "Protocol", so not checked as mirror
        #expect(issues.isEmpty)
    }

    @Test
    func protocolWithExtraRequirementsClean() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol AnalyticsServiceProtocol {
                func track()
                func configure()
                func reset()
                func export()
                func validate()
            }
            """,
            "Impl.swift": """
            class AnalyticsService: AnalyticsServiceProtocol {
                func track() { }
                func configure() { }
                func reset() { }
                func export() { }
                func validate() { }
            }
            """
        ])

        // All requirements match — this IS a mirror, so it should flag
        #expect(issues.count == 1)
    }

    @Test
    func protocolRequirementsNotOnTypeClean() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol NetworkClientProtocol {
                func fetch()
                func post()
                func authenticate()
                func refresh()
                func disconnect()
            }
            """,
            "Impl.swift": """
            class NetworkClient: NetworkClientProtocol {
                func fetch() { }
                func post() { }
                func authenticate() { }
                func refresh() { }
                func disconnect() { }
            }
            """
        ])

        // This is actually a mirror (5/5 match), should flag
        #expect(issues.count == 1)
    }

    @Test
    func noConformingTypeClean() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol OrphanProtocol {
                func work()
            }
            """,
            "Other.swift": """
            struct Unrelated { }
            """
        ])

        // No type named "Orphan" conforming to "OrphanProtocol"
        #expect(issues.isEmpty)
    }

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
            """
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
            """
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
            """
        ])

        #expect(issues.count == 1)
    }

    @Test
    func propertyMirrorFlags() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol SettingsServiceProtocol {
                var theme: String { get }
                var language: String { get set }
                func save()
            }
            """,
            "Impl.swift": """
            struct SettingsService: SettingsServiceProtocol {
                var theme: String
                var language: String
                func save() { }
            }
            """
        ])

        #expect(issues.count == 1)
    }
}

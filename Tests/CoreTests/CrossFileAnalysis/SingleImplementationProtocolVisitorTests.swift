@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct SingleImplementationProtocolVisitorTests {

    private func analyze(
        files: [String: String],
        executablePaths: [String] = []
    ) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = SingleImplementationProtocol().pattern
        let visitor = SingleImplementationProtocolVisitor(fileCache: cache)
        visitor.setPattern(pattern)
        visitor.executableSourcePaths = executablePaths

        for (name, ast) in cache {
            visitor.setFilePath(name)
            visitor.setSourceLocationConverter(SourceLocationConverter(fileName: name, tree: ast))
            visitor.walk(ast)
        }
        visitor.finalizeAnalysis()
        return visitor.detectedIssues.filter { $0.ruleName == .singleImplementationProtocol }
    }

    @Test
    func singleConformerFlags() throws {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol Loadable {
                func load()
            }
            """,
            "Impl.swift": """
            struct DataLoader: Loadable {
                func load() { }
            }
            """
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("Loadable"))
        #expect(issue.message.contains("DataLoader"))
    }

    @Test
    func twoConformersClean() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol Loadable {
                func load()
            }
            """,
            "ImplA.swift": """
            struct DataLoader: Loadable {
                func load() { }
            }
            """,
            "ImplB.swift": """
            struct CacheLoader: Loadable {
                func load() { }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test
    func singleConformerWithMockClean() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol Loadable {
                func load()
            }
            """,
            "Impl.swift": """
            struct DataLoader: Loadable {
                func load() { }
            }
            """,
            "Mock.swift": """
            struct MockLoader: Loadable {
                func load() { }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test
    func zeroConformersFlags() throws {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol Orphan {
                func work()
            }
            """,
            "Other.swift": """
            struct Unrelated { }
            """
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("Orphan"))
        #expect(issue.message.contains("no conformers"))
    }

    @Test
    func publicProtocolClean() {
        let issues = analyze(files: [
            "Protocol.swift": """
            public protocol PublicAPI {
                func call()
            }
            """,
            "Impl.swift": """
            struct Client: PublicAPI {
                func call() { }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    /// A public protocol in an executable/app target has no external consumers,
    /// so the library-API exemption does not apply and it is still flagged.
    @Test
    func publicProtocolInExecutableTargetFlags() throws {
        let issues = analyze(
            files: [
                "Sources/CLI/Protocol.swift": """
                public protocol Runnable {
                    func run()
                }
                """,
                "Sources/CLI/Impl.swift": """
                struct Runner: Runnable {
                    func run() { }
                }
                """
            ],
            executablePaths: ["Sources/CLI/"]
        )

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("Runnable"))
    }

    /// A standalone library project — one that declares no executable target, so
    /// `executableSourcePaths` is empty — keeps the public-API exemption: the
    /// protocol may be conformed to by an external module the analysis can't see.
    @Test
    func publicProtocolInPureLibraryProjectClean() {
        let issues = analyze(
            files: [
                "Sources/MyLib/Protocol.swift": """
                public protocol Runnable {
                    func run()
                }
                """,
                "Sources/MyLib/Impl.swift": """
                struct Runner: Runnable {
                    func run() { }
                }
                """
            ],
            executablePaths: []
        )

        #expect(issues.isEmpty)
    }

    /// Once the project ships an executable, even a library *target* in it is
    /// implementation detail, not a published API — so a single-conformer public
    /// protocol there is flagged, not exempt.
    @Test
    func publicProtocolInLibraryTargetOfExecutableProjectFlags() throws {
        let issues = analyze(
            files: [
                "Sources/MyLib/Protocol.swift": """
                public protocol Runnable {
                    func run()
                }
                """,
                "Sources/MyLib/Impl.swift": """
                struct Runner: Runnable {
                    func run() { }
                }
                """
            ],
            executablePaths: ["Sources/CLI/"]
        )

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("Runnable"))
    }

    /// Regression test for the nested-package blind spot. When the project ships an
    /// executable (CLI/app), its first-party nested packages are implementation
    /// detail, not a published API. A single-conformer `public` protocol declared in
    /// such a package is therefore flagged — the library-API exemption no longer
    /// silences it merely because the protocol is `public` for cross-module
    /// visibility within the same first-party project. Mirrors the real-world
    /// `FileDiscoveryProtocol`/`DefaultFileDiscovery` pair that previously slipped
    /// through.
    @Test
    func publicProtocolInFirstPartyNestedPackageFlags() throws {
        let issues = analyze(
            files: [
                "Packages/Config/Sources/Config/FileDiscovery.swift": """
                public protocol FileDiscoveryProtocol {
                    func findSwiftFiles() -> [String]
                }
                """,
                "Packages/Config/Sources/Config/DefaultFileDiscovery.swift": """
                public struct DefaultFileDiscovery: FileDiscoveryProtocol {
                    public func findSwiftFiles() -> [String] { [] }
                }
                """
            ],
            executablePaths: ["Sources/CLI/", "Sources/App/"]
        )

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("FileDiscoveryProtocol"))
        #expect(issue.message.contains("DefaultFileDiscovery"))
    }

    @Test
    func protocolInTestFileClean() {
        let issues = analyze(files: [
            "Tests/TestHelpers.swift": """
            protocol TestHelper {
                func setup()
            }
            """,
            "Tests/MyTest.swift": """
            struct HelperImpl: TestHelper {
                func setup() { }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    @Test
    func fakeConformerCountsAsMock() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol Repository {
                func fetch()
            }
            """,
            "Impl.swift": """
            struct RealRepository: Repository {
                func fetch() { }
            }
            """,
            "Fakes.swift": """
            struct FakeRepository: Repository {
                func fetch() { }
            }
            """
        ])

        #expect(issues.isEmpty)
    }

    // MARK: - Test-aware suppression

    @Test
    func conformerInTestFileSuppresses() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol Cacheable {
                func cache()
            }
            """,
            "Impl.swift": """
            struct DiskCache: Cacheable {
                func cache() { }
            }
            """,
            "Tests/CacheTests.swift": """
            struct InMemoryCache: Cacheable {
                func cache() { }
            }
            """
        ])
        // 1 prod conformer + 1 test conformer → suppressed
        #expect(issues.isEmpty)
    }

    @Test
    func conformerInMocksFolderSuppresses() {
        let issues = analyze(files: [
            "Protocol.swift": """
            protocol Storable {
                func store()
            }
            """,
            "Impl.swift": """
            struct RealStore: Storable {
                func store() { }
            }
            """,
            "Mocks/TestStore.swift": """
            struct TestStore: Storable {
                func store() { }
            }
            """
        ])
        #expect(issues.isEmpty)
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
}

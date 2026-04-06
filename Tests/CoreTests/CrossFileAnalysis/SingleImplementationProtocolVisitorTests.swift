import Testing
import SwiftSyntax
import SwiftParser
@testable import Core
@testable import SwiftProjectLintRules

@Suite
struct SingleImplementationProtocolVisitorTests {

    private func analyze(files: [String: String]) -> [LintIssue] {
        var cache: [String: SourceFileSyntax] = [:]
        for (name, source) in files {
            cache[name] = Parser.parse(source: source)
        }
        let pattern = SingleImplementationProtocol().pattern
        let visitor = SingleImplementationProtocolVisitor(fileCache: cache)
        visitor.setPattern(pattern)

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
}

@testable import Core
import Testing

/// Core detection: how many conformers a protocol has, and where they live.
@Suite
struct SingleImplementationProtocolVisitorTests {

    func analyze(
        files: [String: String],
        executablePaths: [String] = []
    ) -> [LintIssue] {
        SingleImplementationProtocolTestSupport.analyze(
            files: files, executablePaths: executablePaths
        )
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
            """,
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
            """,
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
            """,
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
            """,
        ])

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("Orphan"))
        #expect(issue.message.contains("no conformers"))
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
            """,
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
            """,
        ])

        #expect(issues.isEmpty)
    }
}

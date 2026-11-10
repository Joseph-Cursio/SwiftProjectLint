@testable import Core
import Testing

extension SingleImplementationProtocolVisitorTests {
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
            """,
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
            """,
        ])
        #expect(issues.isEmpty)
    }
}

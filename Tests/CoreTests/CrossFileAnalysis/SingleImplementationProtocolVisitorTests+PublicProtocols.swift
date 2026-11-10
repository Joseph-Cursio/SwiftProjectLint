@testable import Core
import SwiftParser
import SwiftSyntax
import Testing

extension SingleImplementationProtocolVisitorTests {
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
            """,
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
                """,
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
                """,
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
                """,
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
                """,
            ],
            executablePaths: ["Sources/CLI/", "Sources/App/"]
        )

        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message.contains("FileDiscoveryProtocol"))
        #expect(issue.message.contains("DefaultFileDiscovery"))
    }
}

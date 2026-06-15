@testable import Core
import Foundation
import SwiftSyntax
import Testing

/// Exercises `ProjectLinter`'s dependency-injection seams with lightweight fakes.
///
/// These tests are the reason `FileDiscoveryProtocol` and `CrossFileAnalyzerProtocol`
/// earn their place: substituting fakes lets the linter's orchestration be verified
/// without touching the real filesystem or running the real cross-file engine. Until
/// these existed both protocols were single-conformer abstractions whose testing
/// rationale was unrealized.
@Suite
struct ProjectLinterInjectionTests {

    // MARK: - Fakes

    /// Returns a fixed file list and records the arguments it was asked for.
    private final class FakeFileDiscovery: FileDiscoveryProtocol, @unchecked Sendable {
        struct Call {
            let directory: String
            let excludedPaths: [String]
            let includeNestedPackages: Bool
        }

        let files: [String]
        private let lock = NSLock()
        private var calls: [Call] = []

        init(files: [String]) { self.files = files }

        var recordedCalls: [Call] {
            lock.withLock { calls }
        }

        func findSwiftFiles(
            in directory: String, excludedPaths: [String], includeNestedPackages: Bool
        ) async -> [String] {
            lock.withLock {
                calls.append(
                    Call(
                        directory: directory,
                        excludedPaths: excludedPaths,
                        includeNestedPackages: includeNestedPackages
                    )
                )
            }
            return files
        }
    }

    /// Returns canned issues from cross-file analysis and records that it ran,
    /// without doing any real multi-file work.
    private final class FakeCrossFileAnalyzer: CrossFileAnalyzerProtocol, @unchecked Sendable {
        var enabledFrameworkAllowlists: Set<String>?
        var executableSourcePaths: [String] = []

        let issues: [LintIssue]
        private let lock = NSLock()
        private var invocations = 0

        init(issues: [LintIssue]) { self.issues = issues }

        var callCount: Int {
            lock.withLock { invocations }
        }

        func detectCrossFilePatterns(
            projectFiles _: [ProjectFile],
            categories _: [PatternCategory]?,
            preBuiltCache _: [String: SourceFileSyntax]?
        ) -> [LintIssue] {
            record()
            return issues
        }

        func detectCrossFilePatterns(
            projectFiles _: [ProjectFile],
            ruleIdentifiers _: [RuleIdentifier],
            preBuiltCache _: [String: SourceFileSyntax]?
        ) -> [LintIssue] {
            record()
            return issues
        }

        private func record() {
            lock.withLock { invocations += 1 }
        }
    }

    private func sentinelIssue() -> LintIssue {
        LintIssue(
            severity: .warning,
            message: "cross-file sentinel",
            filePath: "Sentinel.swift",
            lineNumber: 1,
            suggestion: "",
            ruleName: .singleImplementationProtocol
        )
    }

    // MARK: - Tests

    /// The cross-file analyzer's output is merged into the result, and file
    /// discovery is consulted — all without a real filesystem or engine.
    @Test
    func mergesCrossFileAnalyzerOutputAndConsultsDiscovery() async throws {
        let discovery = FakeFileDiscovery(files: [])
        let analyzer = FakeCrossFileAnalyzer(issues: [sentinelIssue()])
        let linter = ProjectLinter(
            fileDiscovery: discovery,
            crossFileAnalyzerFactory: { _ in analyzer }
        )

        let issues = await linter.analyzeProject(at: "/tmp/project-under-test")

        #expect(issues.contains { $0.message == "cross-file sentinel" })
        #expect(analyzer.callCount == 1)
        let call = try #require(discovery.recordedCalls.first)
        #expect(call.directory == "/tmp/project-under-test")
        #expect(discovery.recordedCalls.count == 1)
    }

    /// Per-file analysis covers exactly the files discovery returns: a returned file
    /// with a violation produces issues, and an empty list produces none.
    @Test
    func analyzesOnlyTheFilesDiscoveryReturns() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PLInjection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let badFile = directory.appendingPathComponent("Bad.swift")
        try """
        import Foundation
        func work() {
            let name: String? = nil
            print(name!)
        }
        """.write(to: badFile, atomically: true, encoding: .utf8)

        // A real configured detector so per-file rules actually fire; the seam under
        // test is file discovery, not the (separately injected) detector.
        let detector = PatternRegistryFactory.createConfiguredSystem().detector

        // Discovery returns the file → it is analyzed → at least one per-file issue.
        let withFile = ProjectLinter(
            fileDiscovery: FakeFileDiscovery(files: [badFile.path]),
            crossFileAnalyzerFactory: { _ in FakeCrossFileAnalyzer(issues: []) }
        )
        let foundIssues = await withFile.analyzeProject(at: directory.path, detector: detector)
        #expect(foundIssues.isEmpty == false)

        // Discovery returns nothing → nothing is analyzed → no issues (cross-file empty too).
        let withoutFile = ProjectLinter(
            fileDiscovery: FakeFileDiscovery(files: []),
            crossFileAnalyzerFactory: { _ in FakeCrossFileAnalyzer(issues: []) }
        )
        let emptyIssues = await withoutFile.analyzeProject(at: directory.path, detector: detector)
        #expect(emptyIssues.isEmpty)
    }

    /// File discovery receives the exclusion paths and nested-package flag derived
    /// from the configuration, confirming the seam forwards effective config.
    @Test
    func forwardsConfigurationToFileDiscovery() async throws {
        let discovery = FakeFileDiscovery(files: [])
        let linter = ProjectLinter(
            fileDiscovery: discovery,
            crossFileAnalyzerFactory: { _ in FakeCrossFileAnalyzer(issues: []) }
        )

        let configuration = LintConfiguration(
            excludedPaths: ["Generated"],
            includeNestedPackages: true
        )
        _ = await linter.analyzeProject(
            at: "/tmp/project-under-test",
            configuration: configuration
        )

        let call = try #require(discovery.recordedCalls.first)
        #expect(call.includeNestedPackages)
        #expect(call.excludedPaths.contains("Generated"))
    }
}

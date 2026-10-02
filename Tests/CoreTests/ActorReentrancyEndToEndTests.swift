@testable import Core
import Foundation
import Testing

@Suite
struct ActorReentrancyEndToEndTests {

    /// End-to-end: the `mutating func` pre-scan must reach Actor Reentrancy, so a gate updated
    /// through a method declared in another file counts as updated. The control actor in the same
    /// run never updates its gate, proving the rule is active and the exemption targeted.
    @Test func testActorReentrancySeesMutatingMethodFromAnotherFile() async {
        let root = makeProjectWithGateTypeInAnotherFile()
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()

        let issues = await linter.analyzeProject(at: root, detector: system.detector)
        let reentrancy = issues.filter { $0.ruleName == .actorReentrancy }

        #expect(reentrancy.contains { $0.message.contains("runIfDue") } == false)
        #expect(reentrancy.contains { $0.message.contains("runCarelessly") })
    }

    private func makeProjectWithGateTypeInAnotherFile() -> String {
        let root = makeTempPackageRoot(named: "MutatingGate")
        writeFile(at: "\(root)/Sources/Root/RunGate.swift", """
        import Foundation

        struct RunGate {
            private var lastAttempt: Date?
            func isDue(at now: Date) -> Bool { lastAttempt == nil }
            mutating func recordAttempt(at now: Date) { lastAttempt = now }
        }
        """)
        writeFile(at: "\(root)/Sources/Root/Engines.swift", """
        import Foundation

        actor GuardedEngine {
            var gate = RunGate()

            func runIfDue(at now: Date) async throws -> [String] {
                guard gate.isDue(at: now) else { return [] }
                gate.recordAttempt(at: now)
                return try await work()
            }

            private func work() async throws -> [String] { [] }
        }

        actor CarelessEngine {
            var gate = RunGate()

            func runCarelessly(at now: Date) async throws -> [String] {
                guard gate.isDue(at: now) else { return [] }
                return try await work()
            }

            private func work() async throws -> [String] { [] }
        }
        """)
        return root
    }

    private func makeTempPackageRoot(named: String) -> String {
        let base = FileManager.default.temporaryDirectory.path
        let root = (base as NSString).appendingPathComponent("\(named)-\(UUID().uuidString)")
        writeFile(at: "\(root)/Package.swift", "// swift-tools-version:6.0\n")
        return root
    }

    private func writeFile(at path: String, _ content: String) {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

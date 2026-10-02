@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// A gate updated through a `mutating func` the project declares (`gate.recordAttempt(at:)`) is
/// updated, wherever that type is declared. The standard-library mutators are covered in
/// `ActorReentrancyVisitorTests`.
@Suite
struct ActorReentrancyMutatingMethodTests {

    private func makeVisitor() -> ActorReentrancyVisitor {
        ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
    }

    private func runVisitor(_ visitor: ActorReentrancyVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    /// The SwiftAssist shape that motivated `knownMutatingMethods`: the gate is a struct whose
    /// update is a `mutating func`, declared in the same file here.
    @Test
    func noIssue_sameFileMutatingMethodUpdatesGateBeforeAwait() {
        let source = """
        struct RunGate {
            private var lastAttempt: Date?
            func isDue(at now: Date) -> Bool { lastAttempt == nil }
            mutating func recordAttempt(at now: Date) { lastAttempt = now }
        }

        actor InsightsEngine {
            var gate = RunGate()

            func runIfDue(at now: Date) async throws -> [String] {
                guard gate.isDue(at: now) else { return [] }
                gate.recordAttempt(at: now)
                return try await runAnalysis()
            }

            private func runAnalysis() async throws -> [String] { [] }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    /// The gate type lives in another file, so only the pre-scan knows `recordAttempt` mutates.
    @Test
    func noIssue_preScannedMutatingMethodUpdatesGateBeforeAwait() {
        let source = """
        actor SkillConflictDetector {
            var gate = RunGate()

            func scanIfDue(at now: Date) async throws -> Int? {
                guard gate.isDue(at: now) else { return nil }
                self.gate.recordAttempt(at: now)
                return try await scan()
            }

            private func scan() async throws -> Int { 0 }
        }
        """

        let visitor = makeVisitor()
        visitor.knownMutatingMethods = ["recordAttempt"]
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    /// Without the pre-scan, a gate type from another file is unknown, and the rule keeps its
    /// conservative answer rather than guessing that any call is a write.
    @Test
    func stillDetects_unknownMethodOnGateWithoutPreScan() throws {
        let source = """
        actor SkillConflictDetector {
            var gate = RunGate()

            func scanIfDue(at now: Date) async throws -> Int? {
                guard gate.isDue(at: now) else { return nil }
                gate.recordAttempt(at: now)
                return try await scan()
            }

            private func scan() async throws -> Int { 0 }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("gate"))
    }

    /// A non-mutating method on the gate is a read, not an update.
    @Test
    func stillDetects_nonMutatingMethodOnGate() throws {
        let source = """
        struct RunGate {
            private var lastAttempt: Date?
            func isDue(at now: Date) -> Bool { lastAttempt == nil }
            func describe() -> String { "gate" }
            mutating func recordAttempt(at now: Date) { lastAttempt = now }
        }

        actor InsightsEngine {
            var gate = RunGate()

            func runIfDue(at now: Date) async throws -> [String] {
                guard gate.isDue(at: now) else { return [] }
                _ = gate.describe()
                return try await runAnalysis()
            }

            private func runAnalysis() async throws -> [String] { [] }
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("gate"))
    }

    /// Updating the gate only after the `await` leaves the window open.
    @Test
    func stillDetects_mutatingMethodAfterAwait() throws {
        let source = """
        actor InsightsEngine {
            var gate = RunGate()

            func runIfDue(at now: Date) async throws -> [String] {
                guard gate.isDue(at: now) else { return [] }
                let result = try await runAnalysis()
                gate.recordAttempt(at: now)
                return result
            }

            private func runAnalysis() async throws -> [String] { [] }
        }
        """

        let visitor = makeVisitor()
        visitor.knownMutatingMethods = ["recordAttempt"]
        runVisitor(visitor, source: source)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("gate"))
    }
}

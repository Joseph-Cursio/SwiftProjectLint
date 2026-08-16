@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The rule reports a *contradiction*, so the two halves that matter are: it
/// fires when the author claimed clock-determinism and the body refutes it, and
/// it stays silent in every other combination. The silence half is the larger
/// one — a rule that reported unannotated clock reads would be duplicating
/// `nonInjectedNondeterminism` while pretending the author had said something.
@Suite
struct ContradictedClockDeterminismVisitorTests {

    private func analyze(_ source: String, filePath: String = "Logic.swift") -> [LintIssue] {
        let visitor = ContradictedClockDeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .contradictedClockDeterminism }
    }

    @Test func flagsAttributeClaimContradictedByDate() {
        let source = """
        @ClockDeterministic
        func stale() async -> Date { Date() }
        """
        let issues = analyze(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Date()") == true)
        #expect(issues.first?.message.contains("stale") == true)
    }

    @Test func flagsDocCommentClaimContradictedByTaskSleep() {
        let source = """
        /// @lint.determinism clock_deterministic
        func debounce() async throws { try await Task.sleep(for: .seconds(1)) }
        """
        let issues = analyze(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Task.sleep") == true)
    }

    @Test func flagsClaimContradictedByALocallyConstructedClock() {
        // The acquisition is in this body even though the *use* looks injected.
        let source = """
        @ClockDeterministic
        func tick() async -> ContinuousClock.Instant {
            let clock = ContinuousClock()
            return clock.now
        }
        """
        #expect(analyze(source).count == 1)
    }

    @Test func flagsClaimContradictedInsideANestedClosure() {
        let source = """
        @ClockDeterministic
        func schedule() async { Task { let stamp = Date(); print(stamp) } }
        """
        #expect(analyze(source).count == 1)
    }

    // MARK: - Silence

    /// The guard that keeps this from becoming a rule about unannotated code.
    /// `nonInjectedNondeterminism` covers that, and says something different.
    @Test func ignoresUnannotatedClockReads() {
        #expect(analyze("func stamp() -> Date { Date() }").isEmpty)
    }

    @Test func ignoresAnHonestClaimOnAnInjectedClock() {
        let source = """
        @ClockDeterministic
        func debounce<C: Clock>(clock: C) async throws {
            try await Task.sleep(for: .seconds(1), tolerance: nil, clock: clock)
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresAClaimWhoseOnlyTimeIsAFixedReferencePoint() {
        let source = """
        @ClockDeterministic
        func epoch() async -> Date { Date(timeIntervalSince1970: 0) }
        """
        #expect(analyze(source).isEmpty)
    }

    /// Randomness is not the claim's subject. `@ClockDeterministic` says the
    /// result does not vary with wall-clock time; it says nothing about a UUID,
    /// and refuting on one would contradict an annotation that is honest.
    @Test func ignoresNonClockNondeterminismUnderTheClaim() {
        let source = """
        @ClockDeterministic
        func identify() async -> UUID { UUID() }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresTestFiles() {
        let source = """
        @ClockDeterministic
        func stale() async -> Date { Date() }
        """
        #expect(analyze(source, filePath: "LogicTests.swift").isEmpty)
    }
}

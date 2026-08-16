@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

@Suite
struct NonInjectedNondeterminismVisitorTests {

    private func analyze(_ source: String, filePath: String = "Logic.swift") -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .nonInjectedNondeterminism }
    }

    @Test func flagsInlineDateInit() {
        let source = "func stamp() -> Date { return Date() }"
        #expect(analyze(source).count == 1)
    }

    @Test func flagsInlineUUID() {
        #expect(analyze("func make() -> UUID { UUID() }").count == 1)
    }

    @Test func flagsRandomCall() {
        #expect(analyze("func roll() -> Int { Int.random(in: 1...6) }").count == 1)
    }

    @Test func flagsRandomElementAndShuffled() {
        let source = """
        func pick(_ xs: [Int]) -> Int? { xs.randomElement() }
        func mix(_ xs: [Int]) -> [Int] { xs.shuffled() }
        """
        #expect(analyze(source).count == 2)
    }

    @Test func flagsLegacyCFunctions() {
        #expect(analyze("func r() -> UInt32 { arc4random() }").count == 1)
    }

    @Test func flagsDateNowAndCurrentLocale() {
        let source = """
        func a() -> Date { Date.now }
        func b() -> Locale { Locale.current }
        """
        #expect(analyze(source).count == 2)
    }

    // MARK: - Not flagged

    @Test func ignoresParameterDefaultValue() {
        // The injection seam — not inline use.
        let source = "func make(id: UUID = UUID(), at: Date = Date()) {}"
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresDeterministicInitializers() {
        // Given their input, these are deterministic.
        let source = """
        func a() -> Date { Date(timeIntervalSince1970: 0) }
        func b() -> UUID { UUID(uuidString: "x")! }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresTestFiles() {
        let source = "func roll() -> Int { Int.random(in: 1...6) }"
        #expect(analyze(source, filePath: "RollTests.swift").isEmpty)
    }

    // MARK: - Injected RNG via `using:` is the testable form, not a finding

    @Test func ignoresRandomWithInjectedRNG() {
        let source = """
        func roll(using rng: inout some RandomNumberGenerator) -> Int {
            Int.random(in: 1...6, using: &rng)
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresRandomElementAndShuffledWithInjectedRNG() {
        let source = """
        func pick(_ xs: [Int], using rng: inout some RandomNumberGenerator) -> Int? {
            xs.randomElement(using: &rng)
        }
        func mix(_ xs: [Int], using rng: inout some RandomNumberGenerator) -> [Int] {
            xs.shuffled(using: &rng)
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func stillFlagsSystemRandomWithoutUsing() {
        // Regression guard: only the `using:`-injected form is exempt.
        #expect(analyze("func roll() -> Int { Int.random(in: 1...6) }").count == 1)
    }

    // MARK: - Scope held at the pre-migration line
    //
    // The shared classifier knows more time sources than this rule reports.
    // These pin the exclusions, because the failure they guard against is
    // silent: a rule that widens whenever its dependency learns a new spelling
    // has a scope nobody chose. Each of these DOES read a clock — they are
    // `contradicted-clock-determinism`'s subject, not this rule's.

    @Test func ignoresConcreteClockConstruction() {
        let source = """
        func timed() -> Duration { ContinuousClock().measure { } }
        func suspended() -> SuspendingClock.Instant { SuspendingClock().now }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresTaskSleep() {
        let source = """
        func wait() async throws { try await Task.sleep(for: .seconds(1)) }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func ignoresMonotonicClockReads() {
        let source = """
        func ticks() -> UInt64 { mach_absolute_time() }
        func stamp() -> DispatchTime { DispatchTime.now() }
        """
        #expect(analyze(source).isEmpty)
    }

    /// The rule's line is arity — a construction taking no input can only have
    /// come from ambient state. This one takes an argument, so it is out, and
    /// that is a known miss preserved deliberately rather than an oversight.
    @Test func ignoresDateOffsetFromNow() {
        #expect(analyze("func soon() -> Date { Date(timeIntervalSinceNow: 60) }").isEmpty)
    }

    @Test func ignoresReadingAnInjectedClock() {
        let source = """
        func at<C: Clock>(clock: C) -> C.Instant { clock.now }
        """
        #expect(analyze(source).isEmpty)
    }

    /// The non-vacuity guard for the four above. Without it, a `reportedKinds`
    /// set that had emptied itself — or a classifier returning nil for
    /// everything — would satisfy every exclusion test while the rule reported
    /// nothing at all.
    @Test func stillReportsItsOwnScopeAlongsideTheExclusions() {
        let source = """
        func mixed() async throws -> Date {
            try await Task.sleep(for: .seconds(1))
            _ = ContinuousClock()
            return Date()
        }
        """
        let issues = analyze(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Date()") == true)
    }
}

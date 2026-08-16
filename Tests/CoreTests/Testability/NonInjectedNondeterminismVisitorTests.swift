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

    // MARK: - Clock coverage gained with the shared classifier
    //
    // The rule's own marker set never knew the concrete clocks; the leaf's does.
    // These are new reports, and they are the rule's stated subject — a
    // property-based test can no more pin `Task.sleep(for:)` than `Date()`.

    @Test func flagsConcreteClockConstruction() {
        let source = """
        func timed() -> Duration { ContinuousClock().measure { } }
        func suspended() -> SuspendingClock.Instant { SuspendingClock().now }
        """
        #expect(analyze(source).count == 2)
    }

    @Test func flagsTaskSleepOnTheHostClock() {
        let source = """
        func wait() async throws { try await Task.sleep(for: .seconds(1)) }
        """
        #expect(analyze(source).count == 1)
    }

    @Test func ignoresTaskSleepOnASuppliedClock() {
        // The injection seam, exactly as `using:` is for randomness.
        let source = """
        func wait<C: Clock>(clock: C) async throws {
            try await Task.sleep(for: .seconds(1), tolerance: nil, clock: clock)
        }
        """
        #expect(analyze(source).isEmpty)
    }

    @Test func flagsDateOffsetFromNow() {
        // `timeIntervalSinceNow:` reads the clock despite taking an argument —
        // the case a "no-argument initializers only" rule could not express.
        #expect(analyze("func soon() -> Date { Date(timeIntervalSinceNow: 60) }").count == 1)
    }

    @Test func ignoresReadingAnInjectedClock() {
        // The shape the whole clock family exists to make possible.
        let source = """
        func at<C: Clock>(clock: C) -> C.Instant { clock.now }
        """
        #expect(analyze(source).isEmpty)
    }
}

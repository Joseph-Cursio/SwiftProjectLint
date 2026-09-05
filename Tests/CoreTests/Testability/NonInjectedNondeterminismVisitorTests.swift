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

/// `let id = UUID()` on an `Identifiable` type is an identity, not a testability problem.
///
/// The marker is real — the value is unpredictable — but injecting a UUID provider for it enables
/// no law. `Identifiable` is a declaration that the value's whole job is to be distinct: nothing
/// computes with it, and a test that needs a particular id constructs the value with one.
///
/// **This is a narrow gate on purpose.** Measured across the sweep corpus, 14 of 198 findings are
/// `let id = UUID()` and 13 carry the conformance — a 7% narrowing. The rule looks like it wants a
/// much bigger one, separating values that feed a *decision* from values that are merely recorded,
/// and that turns out not to be decidable from the expression's own syntax: `lastRunDate = Date()`
/// reads as a record until you find the later `Date().timeIntervalSince(lastRunDate)` that makes it
/// a bound. Suppressing that shape would hide half of a real defect, so it is left reported.
@Suite("An Identifiable id is not injectable nondeterminism")
struct NonInjectedNondeterminismIdentityTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "Logic.swift", tree: syntax)
        )
        visitor.setFilePath("Logic.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.nonInjectedNondeterminism }
    }

    @Test("an Identifiable id is not reported")
    func identifiableIDIsNotReported() {
        #expect(analyze("""
        struct Issue: Identifiable {
            let id = UUID()
            let message: String
        }
        """).isEmpty)
    }

    @Test("the conformance is required, not the name")
    func plainTypeWithAnIDIsStillReported() {
        // Without `Identifiable`, `id` is just a name. The value may be compared, persisted as a
        // key, or sent over a wire, and nothing here says otherwise.
        #expect(analyze("""
        struct Record {
            let id = UUID()
            let message: String
        }
        """).count == 1)
    }

    @Test("another Identifiable property is still reported")
    func nonIDPropertyIsStillReported() {
        // The gate is about the identity, not about the type. A timestamp on the same struct is a
        // different question and stays open.
        #expect(analyze("""
        struct Issue: Identifiable {
            let id = UUID()
            let createdAt = Date()
        }
        """).count == 1)
    }

    @Test("a local named id inside a function is still reported")
    func localIDIsStillReported() {
        // A local is not a stored identity whatever it is called, and this one could feed anything.
        #expect(analyze("""
        struct Maker: Identifiable {
            let id = UUID()
            func make() -> String {
                let id = UUID()
                return id.uuidString
            }
        }
        """).count == 1)
    }

    @Test("a computed id is still reported")
    func computedIDIsStillReported() {
        // A fresh UUID on every read is not an identity — two reads disagree, which is a defect in
        // its own right rather than something to exempt.
        #expect(analyze("""
        struct Issue: Identifiable {
            var id: UUID { UUID() }
            let message: String
        }
        """).count == 1)
    }

    @Test("the suggestion names the discriminator")
    func suggestionExplainsWhenToInject() {
        // 198 findings with roughly a 1-in-10 hit rate means the message has to help someone
        // triage, since the rule cannot do it for them.
        let issues = analyze("struct Record { let stamp = Date() }")
        #expect(issues.first?.suggestion?.contains("DECISION") == true)
    }
}

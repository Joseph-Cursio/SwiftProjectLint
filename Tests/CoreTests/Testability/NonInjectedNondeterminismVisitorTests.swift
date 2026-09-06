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

    /// A shipped target whose whole job is to serve tests.
    ///
    /// `SwiftLintRuleStudioCoreTestSupport` is a library product, not a `Tests/` folder, so the
    /// filename and folder checks both passed it through — and its helpers are *deliberately*
    /// nondeterministic: a per-test `UserDefaults` suite name, a per-process scratch root. Seven of
    /// the corpus's 164 findings were that one directory. The name is a stated intent.
    @Test func ignoresTestSupportTargets() {
        let source = "func make() -> UUID { UUID() }"
        #expect(analyze(source, filePath: "Sources/FooCoreTestSupport/Helpers.swift").isEmpty)
        #expect(analyze(source, filePath: "Sources/TestHelpers/Isolation.swift").isEmpty)
    }

    /// Non-vacuity for the above, and the line the suffix match has to hold: a folder that merely
    /// *starts* with the marker is production.
    @Test func stillFlagsProductionNearTestSupport() {
        let source = "func make() -> UUID { UUID() }"
        #expect(analyze(source, filePath: "Sources/FooCore/Helpers.swift").count == 1)
        #expect(analyze(source, filePath: "Sources/TestSupportRunner/Run.swift").count == 1)
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

    /// The house spelling in several of these codebases: a SwiftLint `identifier_name` minimum of
    /// three characters makes `id` unavailable as a stored property, so the conformance is
    /// satisfied by a computed `id` over `identifier`. The gate used to require the short name —
    /// asking for one the project's own configuration forbids.
    @Test("an identity reached through a computed id is not reported")
    func identityBehindAComputedIDIsNotReported() {
        #expect(analyze("""
        struct Insight: Identifiable {
            let identifier = UUID()
            let title: String

            var id: UUID { identifier }
        }
        """).isEmpty)
    }

    /// The link is required, not just the conformance. A `UUID` the type's `id` does not return is
    /// a second value rather than the identity, and stays reported.
    @Test("a uuid the computed id does not return is still reported")
    func unlinkedUUIDIsStillReported() {
        #expect(analyze("""
        struct Record: Identifiable {
            let identifier = UUID()
            let trace = UUID()

            var id: UUID { identifier }
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

/// A nondeterministic source on the right of `??` is a different fault, and gets a different
/// message.
///
/// The rest of this rule reports values a test cannot *control*. These are values the code
/// *invents*: `id = model.id ?? UUID()` fires only for a record that was never saved, and when it
/// fires it lies in a plausible shape. Nothing computes with the value in the sense the main
/// message means, which is exactly why the main message is wrong here — its advice ("a value that
/// is only stored and shown needs no seam") waves through every one of these.
///
/// Measured across the sweep corpus before this split: 7 production occurrences in 23
/// repositories, 2 of them live defects. Small, and precise — the whole reason it is separable is
/// that unlike the decision/record distinction, this one *is* visible in local syntax.
@Suite("A `??` fallback onto a nondeterministic source is a fabrication, not a missing seam")
struct NonInjectedNondeterminismFabricationTests {

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

    @Test("the fallback is reported as a fabrication")
    func fallbackIsReportedAsFabrication() {
        let issues = analyze("""
        func stamp(_ model: Model) -> Date { model.createdAt ?? Date() }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
        #expect(issues.first?.message.contains("Date()") == true)
    }

    @Test("the fabrication message does not advise injection")
    func fabricationMessageDoesNotAdviseASeam() {
        // The point of the split. The main suggestion tells a reader to inject the source and says
        // a value that is only stored and shown needs no seam; both are wrong for this shape.
        let suggestion = analyze("""
        func identify(_ model: Model) -> UUID { model.id ?? UUID() }
        """).first?.suggestion
        #expect(suggestion?.contains("will not fix it") == true)
        #expect(suggestion?.contains("Propagate the `nil`") == true)
    }

    @Test("an inline read that is not a fallback keeps the original message")
    func nonFallbackKeepsTheSeamMessage() {
        let issues = analyze("func isExpired(_ token: Token) -> Bool { token.expiry < Date() }")
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    /// The interaction that made the ordering in `report` load-bearing.
    ///
    /// This is the shape of the four MacCloud_server DTO defects: a stored `id` on an
    /// `Identifiable` type, which is exactly what the identity exemption was written to silence.
    /// Checking identity first would have hidden every one of them.
    @Test("an Identifiable id built from a fallback is still reported")
    func identifiableIDFromAFallbackIsStillReported() {
        let issues = analyze("""
        struct Response: Identifiable {
            let id = model.id ?? UUID()
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }

    @Test("a plain Identifiable id is still exempt")
    func plainIdentifiableIDStaysExempt() {
        // Non-vacuity guard for the test above: the exemption still works when there is no `??`.
        #expect(analyze("""
        struct Response: Identifiable {
            let id = UUID()
        }
        """).isEmpty)
    }

    @Test("both fallbacks in a chain are reported")
    func everyFallbackInAChainIsReported() {
        let issues = analyze("""
        func stamp(_ model: Model) -> Date { model.createdAt ?? model.seenAt ?? Date() }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }

    @Test("a source inside the fallback expression is not a fabrication")
    func aReadInsideTheFallbackIsTheOtherFault() {
        // `Date()` here is *in* the recompute, not *as* the fallback — the value is computed, not
        // invented, so it stays the seam message.
        let issues = analyze("""
        func value(_ cached: Date?) -> Date { cached ?? recompute { Date() } }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    @Test("the left-hand side of a `??` is not a fabrication")
    func theLeftSideKeepsTheSeamMessage() {
        let issues = analyze("func pick(_ fallback: Int) -> Int { Int.random(in: 1...6) ?? fallback }")
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    @Test("a parameter default is still exempt on either side of a `??`")
    func parameterDefaultStaysExempt() {
        #expect(analyze("func make(at date: Date = stored ?? Date()) {}").isEmpty)
    }

    /// Verbatim from `SwiftLintRuleStudioCoreTestSupport`, and the reason this gate exists.
    ///
    /// The first version of `isNilCoalescingFallback` walked to any `??` above the node, so it
    /// called this `UUID()` a fabrication. Nothing is fabricated: the fallback is a fresh isolated
    /// `UserDefaults` suite, and the UUID inside it is a genuine identity doing its job. Being the
    /// fallback and sitting somewhere inside one are different facts.
    @Test("a source inside the fallback's arguments is not a fabrication")
    func aSourceInsideTheFallbacksArgumentsIsNotAFabrication() {
        // A raw literal, so the `\(` reaches the parser instead of interpolating into this
        // test file — which is what makes `UUID()` an expression in the analysed source.
        let issues = analyze(#"""
        func make(_ userDefaults: UserDefaults?) -> UserDefaults {
            userDefaults
                ?? UserDefaults(suiteName: "test.Container.\(UUID().uuidString)")
                ?? .standard
        }
        """#)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    @Test("parentheses around the fallback do not hide it")
    func parenthesesAroundTheFallbackDoNotHideIt() {
        // The other half of the gate: `(Date())` is still the fallback, so the walk has to climb
        // through parentheses while refusing call arguments — both parse as a `TupleExpr`.
        let issues = analyze("func stamp(_ recorded: Date?) -> Date { recorded ?? (Date()) }")
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }
}

/// Creating a value because there is none is not fabricating one to fill a hole.
///
/// `ChatViewModel` writes `let sessionID = currentSessionID ?? UUID()` and then, at the end of the
/// same method, `currentSessionID = sessionID`. The corpus sweep reported that as a fabrication and
/// it was wrong: the invented id is not standing in for a real one that exists somewhere else, it
/// *becomes* the session's id, and nothing downstream can be misled about what it was.
///
/// Every true fabrication in the corpus shares the property this one lacks — the invented value has
/// a real counterpart it can disagree with. A write-back removes the counterpart.
///
/// **Suppressed here means reclassified, not silenced.** These fall through to the rule's ordinary
/// message, which is true of them: a test still cannot pin the id. That is why this gate moves the
/// corpus count by zero.
@Suite("A value written back is created, not fabricated")
struct NonInjectedNondeterminismLazyCreationTests {

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

    /// The `ChatViewModel` shape, reduced. This is the finding the fifteenth sweep left standing.
    @Test("a binding written back later is not a fabrication")
    func bindingWrittenBackIsNotAFabrication() {
        let issues = analyze("""
        func save() {
            let sessionID = currentSessionID ?? UUID()
            store.save(sessionID)
            currentSessionID = sessionID
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    /// The non-vacuity guard, and the reason the gate is the write-back rather than the binding:
    /// delete one line and the same code is a fabrication again.
    @Test("the same binding with no write-back is still a fabrication")
    func bindingWithoutWriteBackIsStillAFabrication() {
        let issues = analyze("""
        func save() {
            let sessionID = currentSessionID ?? UUID()
            store.save(sessionID)
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }

    @Test("the one-statement form is recognised too")
    func selfAssignmentIsNotAFabrication() {
        let issues = analyze("""
        func ensure() {
            currentSessionID = currentSessionID ?? UUID()
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    @Test("self. and the bare name are the same storage")
    func selfPrefixDoesNotDefeatTheGate() {
        let issues = analyze("""
        func save() {
            let sessionID = self.currentSessionID ?? UUID()
            currentSessionID = sessionID
        }
        """)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    @Test("a write-back nested in a branch still counts")
    func writeBackInsideABranchCounts() {
        let issues = analyze("""
        func save() {
            let sessionID = currentSessionID ?? UUID()
            if shouldPersist {
                currentSessionID = sessionID
            }
        }
        """)
        #expect(issues.first?.message.contains("Non-injected nondeterminism") == true)
    }

    /// The gate must not reach the DTO defects it sits next to. `self.id = model.id ?? UUID()` has
    /// an assignment in the very same sequence, and its left-hand side is a *different* storage
    /// from the operand the `??` falls back from — which is exactly why those clients receive a
    /// UUID matching no row.
    @Test("assigning into somewhere else is still a fabrication")
    func assigningIntoDifferentStorageIsStillAFabrication() {
        let issues = analyze("""
        struct Response: Identifiable {
            let id: UUID
            init(model: Model) {
                self.id = model.id ?? UUID()
            }
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }

    /// A write-back needs somewhere to write. `attributes.date() ?? Date()` falls back from a call,
    /// so the gate stays shut rather than guessing what storage was meant.
    @Test("a fallback from a call cannot be lazy creation")
    func fallbackFromACallIsStillAFabrication() {
        let issues = analyze("""
        func stamp(_ attributes: Attributes) -> Date {
            let modified = attributes.date() ?? Date()
            return modified
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }

    /// Writing back a *different* value is not a write-back. Guards against matching on the target
    /// alone and exempting anything that happens to assign to it.
    @Test("assigning something else back is still a fabrication")
    func assigningADifferentValueIsStillAFabrication() {
        let issues = analyze("""
        func save() {
            let sessionID = currentSessionID ?? UUID()
            currentSessionID = fallbackSessionID
            store.save(sessionID)
        }
        """)
        #expect(issues.count == 1)
        #expect(issues.first?.message.contains("Fabricated fallback") == true)
    }
}

@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The fourth arm: a read handed straight on as an argument, never examined by the scope that
/// takes it.
///
/// **This is what following the rest of the rule's advice produces.** "Move the clock read to the
/// edge and pass the instant down" is what the ordinary message asks for, and the reader who does
/// it was still told a property-based test could not pin the value — which at a composition root
/// is false about everything that decides. The arm changes the sentence and not the count.
@Suite("Non-Injected Nondeterminism — the composition-root arm")
struct NonInjectedNondeterminismCompositionRootTests {

    private func analyze(_ source: String, filePath: String = "Logic.swift") -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: filePath, tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath(filePath)
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .nonInjectedNondeterminism }
    }

    private func message(_ source: String) -> String {
        analyze(source).first?.message ?? "(no finding)"
    }

    private func isCompositionRoot(_ source: String) -> Bool {
        message(source).hasPrefix("Clock/RNG read at a composition root")
    }

    // MARK: - Reclassified, not removed

    /// The whole contract of this arm. If any of these ever stops reporting, the census that
    /// answers *where does this program touch the clock?* has quietly lost an entry.
    @Test("every composition root is still reported, exactly once", arguments: [
        "func f() { store.approve(on: Date()) }",
        "func f() -> R { R(capturedAt: Date(), items: items) }",
        "func f() { let now = Date(); header(asOf: now); footer(asOf: now) }"
    ])
    func stillReported(source: String) {
        #expect(analyze(source).count == 1)
        #expect(isCompositionRoot(source))
    }

    // MARK: - The inline form

    @Test func inlineArgumentIsACompositionRoot() {
        #expect(isCompositionRoot("func f() { gate.recordAttempt(at: Date()) }"))
    }

    @Test func inlineArgumentToAnInitializerIsACompositionRoot() {
        #expect(isCompositionRoot("func f() -> H { H(status: \"ok\", timestamp: Date()) }"))
    }

    // MARK: - The bound form

    @Test func boundThenOnlyPassedIsACompositionRoot() {
        let source = """
        func body() -> V {
            let now = Date()
            return V(header: header(asOf: now), rows: rows(asOf: now))
        }
        """
        #expect(isCompositionRoot(source))
    }

    /// One use that is not an argument disqualifies the whole binding. This is the direction that
    /// matters: a binding compared once is a decision this scope makes, and calling it a
    /// composition root would tell a reader to stop looking exactly where the defect is.
    @Test func boundThenComparedIsNotACompositionRoot() {
        let source = """
        func f(_ xs: [Item]) -> [Item] {
            let now = Date()
            report(asOf: now)
            return xs.filter { $0.expiry < now }
        }
        """
        #expect(analyze(source).count == 1)
        #expect(!isCompositionRoot(source))
    }

    @Test func boundThenReturnedIsNotACompositionRoot() {
        #expect(!isCompositionRoot("func f() -> Date { let now = Date(); log(at: now); return now }"))
    }

    /// A `var` can be reassigned, so "every reference is an argument" says nothing about what the
    /// value was when it got there.
    @Test func varBindingIsNotACompositionRoot() {
        #expect(!isCompositionRoot("func f() { var now = Date(); log(at: now) }"))
    }

    /// A stored property's initial value is read once per instance and used in other members this
    /// walk cannot see. `WaiverRequestSheet`'s `@State private var openedAt = Date()` is the corpus
    /// instance, and it feeds arithmetic in a computed property two lines below.
    @Test func storedPropertyInitialValueIsNotACompositionRoot() {
        let source = """
        struct S {
            @State private var openedAt = Date()
            var expiry: Date { openedAt.addingTimeInterval(86_400) }
        }
        """
        #expect(!isCompositionRoot(source))
    }

    // MARK: - Receivers are uses, not hand-offs

    /// Every real defect this rule has produced across the corpus reads the clock into a receiver
    /// **and combines it with something from the scope** — a deadline, an elapsed time, a rate-limit
    /// window. That combination is the precision of the arm, not the receiver itself.
    @Test("combining the value with a local or parameter is not a hand-off", arguments: [
        "func f(_ t: TimeInterval) { let deadline = Date().addingTimeInterval(t); wait(until: deadline) }",
        "func f(_ start: Date) -> Double { Date().timeIntervalSince(start) }"
    ])
    func combiningReceiverIsNotACompositionRoot(source: String) {
        #expect(analyze(source).count == 1)
        #expect(!isCompositionRoot(source))
    }

    /// Re-presenting the value and then *not* handing it on is still not a composition root: these
    /// return or interpolate the result rather than passing it to anything.
    @Test("re-presentation alone is not enough — it still has to be handed on", arguments: [
        "func f() -> String { Date.now.formatted(date: .abbreviated, time: .shortened) }",
        "func f() -> String { \"probe_\\(UUID().uuidString).swift\" }"
    ])
    func representationWithoutAHandOffIsNotACompositionRoot(source: String) {
        #expect(analyze(source).count == 1)
        #expect(!isCompositionRoot(source))
    }

    // MARK: - Re-presentation is reached through

    /// **This test asserted the opposite when the arm shipped**, on the reasoning that a receiver is
    /// always the scope using the value. `.timeIntervalSince1970` takes no argument: it is the same
    /// instant as a number, handed to `bind` as an argument. Four of the nine sites the arm could not
    /// reach were this shape (SwiftProjectLint#193), and the distinction is not the receiver but
    /// whether its arguments reach into the scope.
    @Test("a zero-argument member re-presents the value and is reached through", arguments: [
        "func f() { bind(Date.now.timeIntervalSince1970, at: 1) }",
        "func f(_ content: C) { schedule(R(identifier: UUID().uuidString, content: content)) }"
    ])
    func zeroArgumentMemberIsReachedThrough(source: String) {
        #expect(analyze(source).count == 1)
        #expect(isCompositionRoot(source))
    }

    /// Arguments that are leading-dot style options supply nothing from the scope, so the instant is
    /// still only being restated — here into a `String` that is then handed on.
    @Test func formattedThenPassedOnIsACompositionRoot() {
        let source = """
        func export(report: R, as format: F) {
            let stamp = Date.now.formatted(date: .abbreviated, time: .shortened)
            write(Exporter.export(report, as: format, timestamp: stamp))
        }
        """
        #expect(analyze(source).count == 1)
        #expect(isCompositionRoot(source))
    }

    /// One bare identifier in the arguments and the member is treated as combining, because
    /// resolving whether it is a local, a parameter or a static constant is a scope walk — and
    /// guessing it wrong turns a deadline into an end state.
    @Test func anIdentifierArgumentIsNotInert() {
        #expect(!isCompositionRoot("func f(_ s: S) { send(Date().addingTimeInterval(s.window)) }"))
    }

    /// A trailing closure can run anything, so a member carrying one is never re-presentation.
    @Test func aTrailingClosureIsNotInert() {
        #expect(!isCompositionRoot("func f() { send(Date.now.transformed { $0 }) }"))
    }

    // MARK: - The member is named, and the default is refusal

    /// **Argument-inertness was the wrong question and these are the two shapes that show it**
    /// (SwiftProjectLint#193). The first is the arm's own documented counterexample —
    /// `.addingTimeInterval(timeout)` is a deadline — with the timeout spelled as a literal, and a
    /// literal changes nothing about who decided to add an hour. The second combines the read with
    /// a *second clock read*, so it needs no arguments at all and a rule that inspects arguments
    /// cannot see it. Both were reported as composition roots until the gate started naming the
    /// member.
    @Test("a member that computes is refused however inert its arguments", arguments: [
        "func f() { expire(at: Date().addingTimeInterval(3_600)) }",
        "func f() { record(elapsed: Date().timeIntervalSinceNow) }",
        "func f() { schedule(Date().addingTimeInterval(60 * 60)) }"
    ])
    func computingMemberIsNotACompositionRoot(source: String) {
        #expect(analyze(source).count == 1)
        #expect(!isCompositionRoot(source))
    }

    /// `timeIntervalSince1970` measures from a constant and is on the list; `timeIntervalSinceNow`
    /// measures from a second read of the clock and is not. Same prefix, and the whole difference
    /// between restating a value and computing one.
    @Test func theTwoTimeIntervalPrefixesAreSeparated() {
        #expect(isCompositionRoot("func f() { bind(Date().timeIntervalSince1970, at: 1) }"))
        #expect(!isCompositionRoot("func f() { bind(Date().timeIntervalSinceNow, at: 1) }"))
    }

    /// The default is refusal, which is what makes the list safe to maintain: an unlisted member
    /// that really does only re-present gets this rule's ordinary message — what it got before the
    /// arm existed — rather than being told there is nothing to inject.
    @Test func anUnlistedMemberIsRefused() {
        #expect(!isCompositionRoot("func f(_ c: C) { store(DateContainer(date: Date.now.httpHeader), in: c) }"))
    }

    /// `hashValue` takes nothing and reads like a projection, and is deliberately off the list:
    /// Swift seeds hashing per process, so it layers a second source of nondeterminism on the
    /// first rather than restating it.
    @Test func hashValueIsNotARestatement() {
        #expect(!isCompositionRoot("func f() { bucket(UUID().hashValue) }"))
    }

    // MARK: - Arm order

    /// The fresh-read arm is about where the read is *declared*; this one is about what the
    /// surrounding expression does with it. A computed property whose body hands a fresh read on is
    /// the first fault — every access is a separate read however tidily it is passed along.
    @Test func freshReadPerAccessWinsOverCompositionRoot() {
        let source = """
        struct S {
            var stamped: String { format(at: Date()) }
        }
        """
        #expect(message(source).hasPrefix("Fresh read per access"))
    }

    /// A fabricated fallback is an argument in the shapes the corpus contains
    /// (`R(id: model.id ?? UUID())`), so the fabrication arm must be reached first or the defect
    /// it names would be relabelled as an end state.
    @Test func fabricationWinsOverCompositionRoot() {
        let source = "func f(_ model: M) -> R { R(id: model.id ?? UUID()) }"
        #expect(message(source).hasPrefix("Fabricated fallback"))
    }

    // MARK: - The message does not say "no action"

    /// The corpus's one live defect of this shape is `EvalReport(startedAt: Date(), results:)`
    /// written *after* the loop that produced `results`, so the eval history's `started_at` column
    /// held the instant each run finished. Nothing is untestable and nothing is fabricated — the
    /// read is taken at the wrong moment. A message that closed the finding would have hidden it.
    @Test func theSuggestionAsksWhetherTheInstantMatchesItsLabel() {
        let issue = analyze("func f() { save(R(startedAt: Date(), results: results)) }").first
        let suggestion = issue?.suggestion ?? ""
        #expect(suggestion.contains("read at the moment its label"))
        #expect(issue?.severity == .warning)
    }
}

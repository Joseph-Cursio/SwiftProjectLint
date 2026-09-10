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
    /// or an operand: a deadline, an elapsed time, a rate-limit window. None of them is an
    /// argument, and that is the whole precision of the arm.
    @Test("a receiver is the scope using the value, not passing it", arguments: [
        "func f(_ t: TimeInterval) { let deadline = Date().addingTimeInterval(t); wait(until: deadline) }",
        "func f(_ start: Date) -> Double { Date().timeIntervalSince(start) }",
        "func f() { bind(Date.now.timeIntervalSince1970, at: 1) }",
        "func f() -> String { Date.now.formatted(date: .abbreviated, time: .shortened) }",
        "func f() -> String { \"probe_\\(UUID().uuidString).swift\" }"
    ])
    func receiverIsNotACompositionRoot(source: String) {
        #expect(analyze(source).count == 1)
        #expect(!isCompositionRoot(source))
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

import Foundation
import SwiftParser
import SwiftProjectLintModels
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// What the composition-root arm refuses: reads in argument position that the scope is still
/// *using*, and assignment to storage.
///
/// Split from `NondeterminismCompositionRootTests` by length. Every case here is reported exactly
/// once; what is checked is that none of them carries the composition-root sentence, "nothing to
/// inject", because each is a deadline, an elapsed time, a calendar fact or a stored stamp.
@Suite("Non-Injected Nondeterminism — what the composition-root arm refuses")
struct CompositionRootRefusalTests {

    private func analyze(_ source: String) -> [LintIssue] {
        let visitor = NonInjectedNondeterminismVisitor(patternCategory: .testability)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "Logic.swift", tree: syntax))
        visitor.setFilePath("Logic.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == .nonInjectedNondeterminism }
    }

    private func message(_ source: String) -> String {
        analyze(source).first?.message ?? "(no finding)"
    }

    private func isCompositionRoot(_ source: String) -> Bool {
        message(source).hasPrefix("Clock/RNG read at a composition root")
    }

    /// The argument-side mirror of a combining receiver such as `Date().timeIntervalSince(start)`.
    /// Each read sits in argument position, and each callee relates it to another value or reads a
    /// calendar fact out of it, so the scope is using the instant: the first case is the benchmark
    /// with its operands swapped. All of these were labelled composition roots, "nothing to
    /// inject", until `combines(_:)`.
    @Test("an argument to a callee that combines is not a hand-off", arguments: [
        "func f(_ start: Date) -> Double { start.timeIntervalSince(Date()) }",
        "func f(_ start: Date) -> Double { start.distance(to: Date()) }",
        "func f(_ deadline: Date) -> Bool { deadline.compare(Date()) == .orderedAscending }",
        "func f(_ deadline: Date) -> Date { max(Date(), deadline) }",
        "func f(_ window: DateInterval) -> Bool { window.contains(Date()) }",
        "func f(_ start: Date) -> Double { DateInterval(start: start, end: Date()).duration }",
        "func f(_ start: Date, _ c: Calendar) -> Int? { c.dateComponents([.second], from: start, to: Date()).second }",
        "func f(_ c: Calendar) -> Int { c.component(.hour, from: Date()) }",
        "func f(_ c: Calendar) -> Date? { c.date(byAdding: .day, value: 1, to: Date()) }",
        "func f(_ c: Calendar) -> Date { c.startOfDay(for: Date()) }",
        "func f(_ fmt: Formatter, _ d: Date) -> String { fmt.localizedString(for: d, relativeTo: Date()) }",
        "func f() -> Date { Date(timeInterval: 60, since: Date()) }",
        "func f(_ start: Date) -> Double { max(Date().timeIntervalSince1970, start.timeIntervalSince1970) }",
        // An initializer named by `init` rather than its type, and one that names no type at all.
        "func f(_ t0: Date) -> Double { DateInterval.init(start: t0, end: Date()).duration }",
        "func f(_ t0: Date) -> Double { let i: DateInterval = .init(start: t0, end: Date()); return i.duration }",
        // A span is two operands whatever the callee is called.
        "func f(_ start: Date) -> Double { span(from: start, to: Date()) }",
        // The rest of Calendar and TimeZone.
        "func f(_ c: Calendar) -> Range<Int>? { c.range(of: .day, in: .month, for: Date()) }",
        "func f(_ c: Calendar) -> Int? { c.ordinality(of: .day, in: .year, for: Date()) }",
        "func f(_ c: Calendar) -> DateInterval? { c.nextWeekend(startingAfter: Date()) }",
        "func f(_ tz: TimeZone) -> Int { tz.secondsFromGMT(for: Date()) }",
        "func f(_ tz: TimeZone) -> Bool { tz.isDaylightSavingTime(for: Date()) }",
        "func f(_ end: Date) { for t in stride(from: Date(), through: end, by: 60) { tick(t) } }",
    ])
    func combiningCalleeIsNotACompositionRoot(source: String) {
        #expect(analyze(source).count == 1)
        #expect(isCompositionRoot(source) == false, "\(message(source))")
    }

    /// The benchmark's bound spelling: two reads, each bound and only ever passed to `DateInterval`.
    /// Every reference is an argument, so the bound form accepted both until the callee counted.
    @Test func boundReadsCombinedByTheirCalleeAreNotCompositionRoots() {
        let source = """
        func bench() -> TimeInterval {
            let initialTime = Date()
            work()
            let timeAfter = Date()
            return DateInterval(start: initialTime, end: timeAfter).duration
        }
        """
        let issues = analyze(source)
        #expect(issues.count == 2)
        #expect(issues.allSatisfy { $0.message.hasPrefix("Clock/RNG read at a composition root") == false })
    }

    /// The other side of the line: a formatter that only renders the instant, and a call that only
    /// takes it, are still composition roots. `combines(_:)` keys on the callee, not on the call
    /// having more than one argument.
    @Test("a callee that only takes or renders the instant still hands it on", arguments: [
        "func f(_ formatter: DateFormatter) { show(formatter.string(from: Date())) }",
        "func f(_ formatter: DateFormatter) { send(formatter.string(from: Date()), to: peer) }",
        "func f() { store.approve(proposalID: id, by: reviewer, on: Date()) }",
    ])
    func nonCombiningCalleeStillHandsOn(source: String) {
        #expect(analyze(source).count == 1)
        #expect(isCompositionRoot(source), "\(message(source))")
    }

    /// An initializer is known by its type however it is spelled. The `start:`/`end:` pair already
    /// catches `DateInterval.init(start:end:)` above, so this pins the name on its own.
    @Test("an explicit initializer is named by its type", arguments: [
        ("DateInterval(start: a, end: b)", "DateInterval"),
        ("DateInterval.init(start: a, end: b)", "DateInterval"),
        ("Foundation.DateInterval.init(start: a, end: b)", "DateInterval"),
        (".init(start: a, end: b)", nil),
        ("max<Date>(a, b)", "max"),
        ("calendar.date(byAdding: .day, value: 1, to: a)", "date"),
    ] as [(String, String?)])
    func calleeNameOfAnInitializer(expression: String, expected: String?) throws {
        let call = try #require(OutermostCall.find(in: "_ = \(expression)"))
        #expect(NonInjectedNondeterminismVisitor.calleeName(of: call) == expected)
    }

    /// The first call in source order, which for these fixtures is the outermost one.
    private final class OutermostCall: SyntaxVisitor {
        private var found: FunctionCallExprSyntax?

        static func find(in source: String) -> FunctionCallExprSyntax? {
            let finder = OutermostCall(viewMode: .sourceAccurate)
            finder.walk(Parser.parse(source: source))
            return finder.found
        }

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if found == nil { found = node }
            return .skipChildren
        }
    }

    /// A conversion re-presents, so the question is asked of the conversion: `Int(…)` in arithmetic
    /// is an operand, which a TTL check is. Before the gate stepped through conversions, the read sat
    /// in `Int`'s argument list and these were labelled composition roots.
    @Test("arithmetic on a converted read is not a hand-off", arguments: [
        "func f(_ last: Int) -> Bool { Int(Date().timeIntervalSince1970) - last > 300 }",
        "func f(_ last: Int) -> Bool { let now = Int(Date().timeIntervalSince1970); return now - last > 300 }",
        "func f(_ t0: Double) -> Double { Double(Date().timeIntervalSince1970) - t0 }",
    ])
    func convertedReadInArithmeticIsNotACompositionRoot(source: String) {
        #expect(analyze(source).count == 1)
        #expect(isCompositionRoot(source) == false, "\(message(source))")
    }

    /// And a converted read that is then handed on is still a composition root.
    @Test("a converted read handed on is still a hand-off", arguments: [
        "func f() { bind(Int(Date().timeIntervalSince1970), at: 1) }",
        "func f() { log(String(describing: Date())) }",
        "func f() { let stamp = Int64(Date().timeIntervalSince1970); bind(stamp, at: 1) }",
    ])
    func convertedReadHandedOnIsACompositionRoot(source: String) {
        #expect(analyze(source).count == 1)
        #expect(isCompositionRoot(source), "\(message(source))")
    }

    // MARK: - Assignment to storage stays refused (SwiftProjectLint#193, class A)

    /// **A decision, not a gap.** `x = Date()` records the value and nothing in scope examines it, which
    /// is semantically the same as `store.approve(on: Date())`. Widening the arm to assignment would
    /// also take `self.createdAt = Date()` in an initialiser — a defect this corpus recorded, a client
    /// inventing a creation date only the server knows — and `let signedInAt = Date()` assigned on two
    /// branches, which was the *repair* of first sign-in never being recorded. The defect and its fix
    /// wear the same shape, and the shape is all a gate can see.
    @Test("assignment to storage keeps the ordinary message", arguments: [
        "func f() { lastSyncTime = Date() }",
        "func f(_ user: User) { user.lastLogin = Date() }",
        "struct File { let createdAt: Date; init() { self.createdAt = Date() } }",
        """
        func signIn(_ user: User, first: Bool) {
            let signedInAt = Date()
            if first { user.createdAt = signedInAt } else { user.lastLogin = signedInAt }
        }
        """,
    ])
    func assignmentToStorageIsNotACompositionRoot(source: String) {
        let issues = analyze(source)
        #expect(issues.count == 1)
        #expect(issues.first?.message.hasPrefix("Non-injected nondeterminism") == true, "\(message(source))")
    }
}

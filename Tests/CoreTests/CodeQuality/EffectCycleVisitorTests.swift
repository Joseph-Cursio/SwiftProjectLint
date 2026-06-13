@testable import Core
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// Tests for `EffectCycleVisitor`.
///
/// Detects cycles in a reducer's synchronous `.send(.X)` dispatch graph inside a
/// `switch action`. Sends inside `.run { send in … }` closures (async boundary)
/// are excluded. Motivated by a TCA state-consistency review (`.start` ↔
/// `.refresh`).
@Suite
struct EffectCycleVisitorTests {

    private func makeVisitor() -> EffectCycleVisitor {
        let pattern = EffectCycle().pattern
        return EffectCycleVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: EffectCycleVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Flagged

    @Test("Flags the canonical two-cycle (.start ↔ .refresh)")
    func detectsTwoCycle() throws {
        let source = """
        switch action {
        case .start:
            return .send(.refresh)
        case .refresh:
            return .send(.start)
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .effectCycle)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("refresh"))
        #expect(issue.message.contains("start"))
    }

    @Test("Flags a synchronous self-cycle (.tick → .send(.tick))")
    func detectsSelfCycle() {
        let source = """
        switch action {
        case .tick:
            return .send(.tick)
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("Flags a three-node cycle (a → b → c → a)")
    func detectsThreeCycle() {
        let source = """
        switch action {
        case .a: return .send(.b)
        case .b: return .send(.c)
        case .c: return .send(.a)
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Not flagged

    @Test("No issue for a linear send chain")
    func noIssueForLinearChain() {
        let source = """
        switch action {
        case .start:
            return .send(.load)
        case .load:
            return .none
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when the re-dispatch crosses an async boundary (.run send)")
    func noIssueForRunClosureSend() {
        let source = """
        switch action {
        case .tick:
            return .run { send in
                try await clock.sleep(for: .seconds(1))
                await send(.tick)
            }
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for an async request/response (no synchronous cycle)")
    func noIssueForRequestResponse() {
        let source = """
        switch action {
        case .reload:
            return .run { send in
                let value = try await api.fetch()
                await send(.response(value))
            }
        case let .response(value):
            state.value = value
            return .none
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for a switch that is not on `action`")
    func noIssueForNonActionSwitch() {
        let source = """
        switch state.mode {
        case .start: return .send(.refresh)
        case .refresh: return .send(.start)
        }
        """
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}

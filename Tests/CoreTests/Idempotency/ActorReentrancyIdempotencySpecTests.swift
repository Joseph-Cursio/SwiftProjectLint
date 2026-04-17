import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

/// Verifies that the existing `actorReentrancy` rule aligns with the idempotency
/// proposal's `actorReentrancyIdempotencyHazard` specification — the canonical
/// `processedIDs.contains(id) → await → processedIDs.insert(id)` anti-pattern.
///
/// This is a regression + alignment test for the idempotency trial's Phase 2 gate.
/// The rule was not built by this trial; this fixture documents spec alignment.
@Suite
struct ActorReentrancyIdempotencySpecTests {

    @Test
    func canonicalGuardAwaitInsertPattern_flags() throws {
        // From the design proposal's canonical example:
        //   guard !processedIDs.contains(id) else { return }
        //   try await chargeCard(id)
        //   processedIDs.insert(id)
        //
        // The bug: between the contains check and the insert, the actor's
        // suspension point allows a concurrent caller to pass the same guard
        // and charge the card a second time.
        let source = """
        actor PaymentProcessor {
            var processedIDs: Set<String> = []

            func charge(id: String) async throws {
                guard !processedIDs.contains(id) else { return }
                try await chargeCard(id)
                processedIDs.insert(id)
            }

            private func chargeCard(_ id: String) async throws {}
        }
        """

        let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
        visitor.walk(Parser.parse(source: source))

        // Rule fires on the guard-then-await-then-insert pattern. The precise
        // suppression heuristics in the existing rule (awaitRelatedNames) may
        // interact with the `contains(id)` shape in subtle ways — the concrete
        // expectation for the trial is documented here. If this assertion's
        // count drifts, Phase 5 of the trial records the gap between the rule
        // as shipped and the proposal's spec.
        #expect(visitor.detectedIssues.isEmpty == false)
        if let first = visitor.detectedIssues.first {
            #expect(first.ruleName == .actorReentrancy)
            #expect(first.message.contains("processedIDs"))
        }
    }

    @Test
    func claimBeforeSuspension_noDiagnostic() {
        // The fix pattern from the proposal: claim the slot (insert into
        // processedIDs) BEFORE any suspension point, and compensate in catch.
        // Expected by the proposal: no reentrancy diagnostic.
        //
        // ### Trial finding (spec-alignment gap)
        //
        // The existing `actorReentrancy` rule detects "assignment" only via
        // `SequenceExprSyntax` with `=` — plain or `self.prop =`. It does
        // NOT recognise `Set.insert(_:)` or other mutating-method calls as
        // writes to the stored property. So the proposal's canonical fix
        // pattern ("claim the slot with insert(_:) before await, compensate
        // with remove(_:) in catch") still fires the rule.
        //
        // For the trial Phase 2 gate, this is recorded via `withKnownIssue`
        // so the fixture is shipped and the suite stays green. Phase 5
        // records the gap in the proposal's Open Issues as a candidate
        // refinement of `actorReentrancyIdempotencyHazard`.
        let source = """
        actor PaymentProcessor {
            var processedIDs: Set<String> = []

            func charge(id: String) async throws {
                guard !processedIDs.contains(id) else { return }
                processedIDs.insert(id)
                do {
                    try await chargeCard(id)
                } catch {
                    processedIDs.remove(id)
                    throw error
                }
            }

            private func chargeCard(_ id: String) async throws {}
        }
        """

        withKnownIssue("actorReentrancy rule does not recognise Set.insert(_:) as a write; see Phase 5 trial findings.") {
            let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
            visitor.walk(Parser.parse(source: source))
            #expect(visitor.detectedIssues.isEmpty)
        }
    }
}

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
        //
        // The rule now recognises mutating-method calls on tracked stored
        // properties (Set.insert(_:), Array.append(_:), Dictionary.removeValue(...),
        // etc.) as writes — see ActorReentrancyVisitor.mutatingMethodNames.
        // OI-3 resolved for the common cases; subscript-set (X[k] = v) is still
        // a remaining sub-gap noted in the proposal's Open Issues.
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

        let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
        visitor.walk(Parser.parse(source: source))
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func selfQualifiedMutatingMethodClaim_noDiagnostic() {
        // Same fix pattern, but through self.<prop>.<method>(…) — must also
        // suppress the diagnostic.
        let source = """
        actor PaymentProcessor {
            var processedIDs: Set<String> = []

            func charge(id: String) async throws {
                guard !self.processedIDs.contains(id) else { return }
                self.processedIDs.insert(id)
                try await chargeCard(id)
            }

            private func chargeCard(_ id: String) async throws {}
        }
        """

        let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
        visitor.walk(Parser.parse(source: source))
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func containsCallIsNotMistakenForWrite() throws {
        // Regression guard against over-widening: `processedIDs.contains(id)` is a
        // READ, not a write. If the widening accepted any method call on the
        // property as a write, this fixture would be silently suppressed.
        let source = """
        actor PaymentProcessor {
            var processedIDs: Set<String> = []

            func charge(id: String) async throws {
                guard !processedIDs.contains(id) else { return }
                _ = processedIDs.contains(id)
                try await chargeCard(id)
                processedIDs.insert(id)
            }

            private func chargeCard(_ id: String) async throws {}
        }
        """

        let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
        visitor.walk(Parser.parse(source: source))

        // `insert` is AFTER the await, so no intervening write between guard
        // and await — rule must still fire.
        #expect(visitor.detectedIssues.isEmpty == false)
        #expect(visitor.detectedIssues.first?.message.contains("processedIDs") == true)
    }
}

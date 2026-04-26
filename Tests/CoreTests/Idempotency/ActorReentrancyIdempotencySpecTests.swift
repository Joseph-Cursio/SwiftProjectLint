import Testing
@testable import SwiftProjectLintIdempotencyRules
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

    // MARK: - OI-3 residual — subscript-set claims as writes

    @Test
    func subscriptSetClaim_selfPrefix_flagsAsWrite() throws {
        // The canonical sentinel-set idiom using a dictionary rather than a
        // Set: claim the slot via `self.table[key] = value` before awaiting.
        // Pre-OI-3-residual, this LHS shape wasn't recognised as a write, so
        // the rule would miss the correct fix and fire despite the claim.
        let source = """
        actor PaymentProcessor {
            var table: [String: String] = [:]

            func charge(id: String) async throws {
                guard table[id] == nil else { return }
                self.table[id] = "pending"
                try await chargeCard(id)
            }

            private func chargeCard(_ id: String) async throws {}
        }
        """
        let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
        visitor.walk(Parser.parse(source: source))
        // The claim (`self.table[id] = "pending"`) sits between the guard
        // and the await, so the reentrancy pattern is correctly neutralised.
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func subscriptSetClaim_bareReceiver_flagsAsWrite() throws {
        // Same idiom without the `self.` prefix.
        let source = """
        actor QueueProcessor {
            var queue: [String: String] = [:]

            func enqueue(id: String) async throws {
                guard queue[id] == nil else { return }
                queue[id] = "pending"
                try await persist(id)
            }

            private func persist(_ id: String) async throws {}
        }
        """
        let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
        visitor.walk(Parser.parse(source: source))
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func subscriptSetOnNonTrackedProperty_doesNotSuppress() throws {
        // A subscript-set on a local (NOT a tracked stored property) must
        // not be mistaken for a claim. The guard-then-await without
        // intervening write to the tracked property still fires.
        let source = """
        actor Mixed {
            var table: [String: String] = [:]

            func charge(id: String) async throws {
                guard table[id] == nil else { return }
                var other: [String: String] = [:]
                other[id] = "pending"
                try await chargeCard(id)
                table[id] = "done"
            }

            private func chargeCard(_ id: String) async throws {}
        }
        """
        let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
        visitor.walk(Parser.parse(source: source))
        // `other[id] = "pending"` does NOT claim the `table` slot. Rule fires
        // on the guard / await / post-await-write pattern for `table`.
        #expect(visitor.detectedIssues.isEmpty == false)
        #expect(visitor.detectedIssues.first?.message.contains("table") == true)
    }

    // MARK: - OI-3 residual — compound assignments as writes

    @Test
    func compoundAssign_plusEquals_flagsAsWrite() throws {
        // `count += 1` is a write to `count`. Claim via compound assignment
        // before the await is a valid reentrancy guard.
        let source = """
        actor Counter {
            var count: Int = 0

            func tick(id: String) async throws {
                guard count < 10 else { return }
                count += 1
                try await publish(id)
            }

            private func publish(_ id: String) async throws {}
        }
        """
        let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
        visitor.walk(Parser.parse(source: source))
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func compoundAssign_selfPrefix_flagsAsWrite() throws {
        let source = """
        actor Counter {
            var count: Int = 0

            func tick(id: String) async throws {
                guard self.count < 10 else { return }
                self.count += 1
                try await publish(id)
            }

            private func publish(_ id: String) async throws {}
        }
        """
        let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
        visitor.walk(Parser.parse(source: source))
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func compoundAssign_onSubscript_flagsAsWrite() throws {
        // The combination: `self.totals[id, default: 0] += amount`. Both
        // subscript LHS resolution and compound-assignment operator
        // detection are needed; the fixture exercises both simultaneously.
        let source = """
        actor Accumulator {
            var totals: [String: Int] = [:]

            func add(id: String, amount: Int) async throws {
                guard (totals[id] ?? 0) + amount <= 100 else { return }
                self.totals[id, default: 0] += amount
                try await persist(id)
            }

            private func persist(_ id: String) async throws {}
        }
        """
        let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
        visitor.walk(Parser.parse(source: source))
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func comparisonOperators_notMistakenForWrite() throws {
        // Regression guard: `==`, `!=`, `<=`, `>=` end in `=` but are NOT
        // assignments. The whitelist-based detection must not misclassify
        // them. If this fixture fires more than once or credits a comparison
        // operator as a write, the compound-assignment detection has
        // over-reached.
        let source = """
        actor Gate {
            var count: Int = 0

            func probe(id: String) async throws {
                guard count == 0 else { return }
                try await bootstrap(id)
                count = count + 1
            }

            private func bootstrap(_ id: String) async throws {}
        }
        """
        let visitor = ActorReentrancyVisitor(pattern: ActorReentrancy().pattern)
        visitor.walk(Parser.parse(source: source))
        // Pattern: `guard count == 0 else return` (read) → `try await
        // bootstrap` (suspension) → `count = count + 1` (post-await write).
        // The canonical reentrancy hazard — guard reads `count`, awaits,
        // then writes `count` with no intervening claim. Rule fires on
        // exactly one write site (the `count = count + 1` assignment).
        // Crucially NOT firing on the `==` comparison — that would be the
        // over-reach regression this test guards against.
        #expect(visitor.detectedIssues.count == 1)
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

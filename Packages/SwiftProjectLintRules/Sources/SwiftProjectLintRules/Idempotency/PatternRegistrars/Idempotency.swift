import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Registers patterns related to idempotency contracts for retry-safe code.
///
/// Phase 1 of the idempotency trial: two annotation-gated rules, no inference,
/// per-file symbol table only. See `docs/phase1/trial-scope.md` in the
/// swiftIdempotency repo for the scope commitment.
class Idempotency: BasePatternRegistrar {
    override func registerPatterns() {
        registry.register(registrars: [
            IdempotencyViolation(),
            NonIdempotentInRetryContext(),
            MissingIdempotencyKey(),
            OnceContractViolation(),
            UnannotatedInStrictReplayableContext(),
            TupleEqualityWithUnstableComponents()
        ])
    }
}

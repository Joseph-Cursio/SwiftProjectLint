import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the idempotency-violation pattern.
///
/// Flags calls inside `/// @lint.effect idempotent` functions to callees declared
/// `/// @lint.effect non_idempotent`. Phase 1 of the idempotency trial.
struct IdempotencyViolation: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .idempotencyViolation,
            visitor: IdempotencyViolationVisitor.self,
            severity: .error,
            category: .idempotency,
            messageTemplate: "Idempotency violation: an idempotent-declared function "
                + "calls a non-idempotent-declared function.",
            suggestion: "Replace the non-idempotent callee with an idempotent alternative, "
                + "or weaken the caller's declared effect.",
            description: "Detects functions declared `/// @lint.effect idempotent` whose body "
                + "calls a function declared `/// @lint.effect non_idempotent` in the same file. "
                + "Phase 1: per-file symbol table, no inference, no cross-file propagation."
        )
    }
}

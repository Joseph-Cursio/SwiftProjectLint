import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the once-contract-violation pattern.
///
/// Flags call sites where a callee declared `/// @lint.context once`
/// appears in a position that could re-invoke it: inside a `for` /
/// `while` / `repeat` loop body, or inside a function declared
/// `/// @lint.context replayable` or `/// @lint.context retry_safe`.
///
/// Phase 1 of `@lint.context once`: direct call-site detection only.
/// Transitive multi-hop propagation (a `replayable` body calls an
/// un-annotated helper that calls a `once` callee) is deferred to a
/// follow-up that re-uses the upward-inference call graph.
struct OnceContractViolation: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .onceContractViolation,
            visitor: OnceContractViolationVisitor.self,
            severity: .error,
            category: .idempotency,
            messageTemplate: "Once-contract violation: a `@lint.context once` callee is called "
                + "from a position that could re-invoke it (loop, replayable, or retry_safe body).",
            suggestion: "Either move the call to a position guaranteed to execute at most once "
                + "(e.g. one-time init, idempotency-key-guarded path), or weaken the callee's "
                + "annotation if the once-contract is incorrect.",
            description: "Detects calls to a function declared `/// @lint.context once` from "
                + "within a `for` / `while` / `repeat` loop body or from within a function "
                + "declared `/// @lint.context replayable` or `/// @lint.context retry_safe`. "
                + "Phase 1: direct call-site detection only; transitive propagation via "
                + "un-annotated helpers is deferred."
        )
    }
}

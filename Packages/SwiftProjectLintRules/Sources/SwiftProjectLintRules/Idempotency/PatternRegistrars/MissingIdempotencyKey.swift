import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the missing-idempotency-key pattern.
///
/// Flags call sites whose callee is declared `@lint.effect externally_idempotent(by: P)`
/// and whose argument at label `P` is an obvious per-invocation generator
/// (`UUID()`, `Date()`, `Date.now`, `arc4random()`, etc.). Opaque expressions
/// are not flagged — the rule is deliberately the narrow, high-precision
/// check; deeper data-flow analysis is future work.
struct MissingIdempotencyKey: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .missingIdempotencyKey,
            visitor: MissingIdempotencyKeyVisitor.self,
            severity: .error,
            category: .idempotency,
            messageTemplate: "Idempotency-key argument is not stable across retries.",
            suggestion: "Route a stable upstream identifier (event ID, request ID, "
                + "message ID) into the keyed argument.",
            description: "Verifies that calls to functions declared "
                + "`/// @lint.effect externally_idempotent(by: P)` pass a stable value "
                + "at argument label `P`. Fresh-per-call generators like `UUID()`, "
                + "`Date()`, and `Date.now` break the keyed guarantee because each "
                + "retry produces a different key."
        )
    }
}

import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the non-idempotent-in-retry-context pattern.
///
/// Flags calls inside `/// @lint.context replayable` or `/// @lint.context retry_safe`
/// functions to callees declared `/// @lint.effect non_idempotent`.
struct NonIdempotentInRetryContext: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .nonIdempotentInRetryContext,
            visitor: NonIdempotentInRetryContextVisitor.self,
            severity: .error,
            category: .idempotency,
            messageTemplate: "Non-idempotent call inside a replayable/retry_safe context.",
            suggestion: "Replace the callee with an idempotent alternative, or route through "
                + "a deduplication guard or idempotency-key mechanism.",
            description: "Detects functions declared `/// @lint.context replayable` or "
                + "`/// @lint.context retry_safe` whose body calls a function declared "
                + "`/// @lint.effect non_idempotent`. Phase 1: per-file, no inference."
        )
    }
}

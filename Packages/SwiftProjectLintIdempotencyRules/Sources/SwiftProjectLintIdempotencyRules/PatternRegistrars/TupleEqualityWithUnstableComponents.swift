import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Registrar for the tuple-equality-with-unstable-components rule.
///
/// File-local, annotation-free detection of structurally-invalid tuple
/// equalities — comparisons whose outcome is pinned to a time, randomness,
/// or per-call identity source that changes on every read.
struct TupleEqualityWithUnstableComponents: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .tupleEqualityWithUnstableComponents,
            visitor: TupleEqualityWithUnstableComponentsVisitor.self,
            severity: .warning,
            category: .idempotency,
            messageTemplate: "Tuple equality carries unstable component(s); "
                + "structural equality on time, randomness, or per-call identity "
                + "reads never converges on replay.",
            suggestion: "Compare only the stable subset of fields, or promote the "
                + "tuple to a struct with an `Equatable` conformance tailored to "
                + "the semantic identity you actually want to compare.",
            description: "Detects `(a, b) == (c, d)` and `!=` tuple-literal "
                + "equality where any element on either side is produced by a "
                + "non-idempotent read such as `Date()`, `UUID()`, `.now`, "
                + "`Int.random(in:)`, `CFAbsoluteTimeGetCurrent()`, or carries a "
                + "conventionally-unstable name (`now`, `timestamp`, `nonce`). "
                + "Literal tuples only; variable-referenced tuples would require "
                + "type resolution the rule intentionally does not do."
        )
    }
}

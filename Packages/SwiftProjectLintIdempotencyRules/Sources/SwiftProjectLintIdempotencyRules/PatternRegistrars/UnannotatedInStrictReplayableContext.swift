import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// A registrar for the `unannotatedInStrictReplayableContext` rule.
///
/// Flags calls inside `/// @lint.context strict_replayable` functions to
/// callees whose effect is not declared, upward-inferred, or
/// heuristically classified. Opt-in strict-mode variant of
/// `replayable` — see the round-9 trial retrospective.
struct UnannotatedInStrictReplayableContext: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .unannotatedInStrictReplayableContext,
            visitor: UnannotatedInStrictReplayableContextVisitor.self,
            severity: .error,
            category: .idempotency,
            messageTemplate: "Unannotated call inside a strict_replayable context.",
            suggestion: "Annotate the callee with `/// @lint.effect idempotent` / "
                + "`observational` / `externally_idempotent(by:)`, or use the "
                + "`SwiftIdempotency` attribute forms.",
            description: "Detects functions declared `/// @lint.context strict_replayable` "
                + "whose body calls a function whose effect cannot be proven through "
                + "declaration, upward inference, or heuristic classification. The "
                + "opt-in strict variant of the `replayable` rule's precision profile."
        )
    }
}

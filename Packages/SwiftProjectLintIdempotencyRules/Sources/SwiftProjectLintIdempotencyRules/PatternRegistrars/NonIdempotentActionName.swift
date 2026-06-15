import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the non-idempotent-action-name pattern.
///
/// Flags a `switch` case whose enum case is named like an idempotent action
/// (exact `dismiss`/`close`/`hide`/`select`/`cancel`, or prefix `set`/`show`/
/// `select`) but whose synchronous body mutates non-idempotently — a
/// compound assignment (`+=`/`-=`/`*=`/`/=`/`%=`) or a `.toggle()` call. The
/// name implies "applying it twice == once"; an accumulating/toggling body
/// breaks that contract.
struct NonIdempotentActionName: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .nonIdempotentActionName,
            visitor: NonIdempotentActionNameVisitor.self,
            severity: .warning,
            category: .idempotency,
            messageTemplate: "Action is named like an idempotent action but its body "
                + "mutates non-idempotently.",
            suggestion: "Make the body idempotent (assign a fixed value rather than "
                + "accumulating/toggling), or rename the action to reflect its cumulative "
                + "behavior.",
            description: "Detects a switch case for an enum case named like an idempotent "
                + "action (exact dismiss/close/hide/select/cancel, or prefix set/show/select) "
                + "whose synchronous body contains a compound assignment (+=, -=, *=, /=, %=) "
                + "or a .toggle() call. Such a name promises idempotence — applying the "
                + "action twice equals applying it once — which an accumulating or toggling "
                + "body breaks. Closures (effect bodies) are not inspected."
        )
    }
}

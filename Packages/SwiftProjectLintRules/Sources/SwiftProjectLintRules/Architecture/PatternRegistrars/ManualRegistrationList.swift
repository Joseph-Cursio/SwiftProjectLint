import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the manual-registration-list pattern: a run of consecutive
/// calls to the same registration-verb method, which a data-driven registry
/// would make omission-proof.
struct ManualRegistrationList: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .manualRegistrationList,
            visitor: ManualRegistrationListVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "{count} consecutive {callee} calls form a hand-maintained registration list",
            suggestion: "Drive these from a declared array (a registry) iterated once, so a new "
                + "entry can't be omitted from this list.",
            description: "Detects a run of consecutive calls to the same registration-verb method "
                + "(register…/add…/append/record). An item added elsewhere can be silently left out "
                + "of the list without a compile error; a data-driven registry removes that risk."
        )
    }
}

import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registrar for the Impure Call in View Body rule.
///
/// Flags persistence / IO / logging / scheduling API references inside a SwiftUI
/// view's `body` — `body` should be a pure function of state, so side-effecting
/// calls make rendering nondeterministic and untestable.
struct ImpureCallInViewBody: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .impureCallInViewBody,
            visitor: ImpureCallInViewBodyVisitor.self,
            severity: .warning,
            category: .testability,
            messageTemplate: "Impure call in a SwiftUI view `body` — rendering should be a pure "
                + "function of state.",
            suggestion: "Move the side effect / external-state read out of `body` (an action / "
                + "`onAppear` / `@AppStorage`) and drive the view from state.",
            description: "Detects persistence / IO / logging / scheduling API references inside a "
                + "SwiftUI view's body, which make rendering impure and untestable."
        )
    }
}
